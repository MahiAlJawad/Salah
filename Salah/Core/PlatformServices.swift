@preconcurrency import CoreLocation
@preconcurrency import MapKit
import Foundation
import Observation
import UserNotifications

enum LocationAuthorization: String, Sendable {
    case notDetermined, authorized, denied, restricted

    var title: String {
        switch self {
        case .notDetermined: L10n.string("Not requested")
        case .authorized: L10n.string("Allowed")
        case .denied: L10n.string("Denied")
        case .restricted: L10n.string("Restricted")
        }
    }
}

enum LocationServiceError: LocalizedError {
    case denied, restricted, unavailable, failed(String)

    var errorDescription: String? {
        switch self {
        case .denied: L10n.string("Location access is denied. Search for a city or enable access in Settings.")
        case .restricted: L10n.string("Location access is restricted on this device. Search for a city instead.")
        case .unavailable: L10n.string("Your current location is unavailable.")
        case .failed: L10n.string("The location request failed.")
        }
    }
}

@MainActor
protocol LocationProviding: AnyObject {
    var authorization: LocationAuthorization { get }
    func requestCurrentLocation() async throws -> PrayerLocation
}

@MainActor
@Observable
final class CoreLocationProvider: NSObject, LocationProviding, @preconcurrency CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var authorizationContinuation: CheckedContinuation<Void, Never>?
    private var locationContinuation: CheckedContinuation<PrayerLocation, Error>?

    private(set) var authorization: LocationAuthorization

    override init() {
        manager = CLLocationManager()
        authorization = Self.map(manager.authorizationStatus)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestCurrentLocation() async throws -> PrayerLocation {
        switch authorization {
        case .notDetermined:
            await withCheckedContinuation { continuation in
                authorizationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        case .denied: throw LocationServiceError.denied
        case .restricted: throw LocationServiceError.restricted
        case .authorized: break
        }

        switch authorization {
        case .denied: throw LocationServiceError.denied
        case .restricted: throw LocationServiceError.restricted
        case .notDetermined: throw LocationServiceError.unavailable
        case .authorized:
            return try await withCheckedThrowingContinuation { continuation in
                locationContinuation = continuation
                manager.requestLocation()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = Self.map(manager.authorizationStatus)
        authorizationContinuation?.resume()
        authorizationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let value = locations.last else {
            locationContinuation?.resume(throwing: LocationServiceError.unavailable)
            locationContinuation = nil
            return
        }
        let continuation = locationContinuation
        locationContinuation = nil
        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(value, preferredLocale: L10n.locale).first
            continuation?.resume(returning: PrayerLocation(
                name: Self.displayName(for: value, placemark: placemark),
                latitude: value.coordinate.latitude,
                longitude: value.coordinate.longitude,
                timeZoneIdentifier: placemark?.timeZone?.identifier ?? TimeZone.current.identifier,
                countryCode: placemark?.isoCountryCode,
                source: .automatic
            ))
        }
    }

    private static func displayName(for location: CLLocation, placemark: CLPlacemark?) -> String {
        let cityOrDistrict = [placemark?.locality, placemark?.subAdministrativeArea]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        if let cityOrDistrict {
            let country = placemark?.country?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let country, !country.isEmpty, cityOrDistrict.localizedCaseInsensitiveCompare(country) != .orderedSame {
                return "\(cityOrDistrict), \(country)"
            }
            return cityOrDistrict
        }

        if let administrativeArea = placemark?.administrativeArea, !administrativeArea.isEmpty {
            return administrativeArea
        }

        return L10n.string("Nearby Location")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: LocationServiceError.failed(error.localizedDescription))
        locationContinuation = nil
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .authorized
        @unknown default: .restricted
        }
    }
}

struct LocationSearchSuggestion: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
}

enum LocationSearchError: LocalizedError {
    case unavailable
    case noResults

    var errorDescription: String? {
        switch self {
        case .unavailable: L10n.string("That location is no longer available. Search again.")
        case .noResults: L10n.string("No matching location was found.")
        }
    }
}

@MainActor
protocol LocationSearchProviding: AnyObject {
    func search(_ query: String, completion: @escaping ([LocationSearchSuggestion], String?) -> Void)
    func resolve(_ suggestion: LocationSearchSuggestion) async throws -> PrayerLocation
}

@MainActor
final class MapLocationSearchProvider: NSObject, LocationSearchProviding, @preconcurrency MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var completionHandler: (([LocationSearchSuggestion], String?) -> Void)?
    private var completions: [String: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String, completion: @escaping ([LocationSearchSuggestion], String?) -> Void) {
        completer.cancel()
        completionHandler = completion
        completions.removeAll()
        completer.queryFragment = query
    }

    func resolve(_ suggestion: LocationSearchSuggestion) async throws -> PrayerLocation {
        guard let completion = completions[suggestion.id] else { throw LocationSearchError.unavailable }
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw LocationSearchError.noResults }
        return try Self.prayerLocation(from: item, fallbackName: suggestion.title)
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let suggestions = completer.results.map { completion in
            let id = UUID().uuidString
            completions[id] = completion
            return LocationSearchSuggestion(
                id: id,
                title: completion.title,
                subtitle: completion.subtitle
            )
        }
        completionHandler?(suggestions, nil)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        completionHandler?([], error.localizedDescription)
    }

    static func prayerLocation(from item: MKMapItem, fallbackName: String) throws -> PrayerLocation {
        let placemark = item.placemark
        let coordinate = placemark.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              let timeZone = item.timeZone ?? placemark.timeZone else {
            throw LocationSearchError.noResults
        }

        let name = displayName(
            locality: placemark.locality,
            subAdministrativeArea: placemark.subAdministrativeArea,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country,
            fallback: item.name ?? fallbackName
        )
        return PrayerLocation(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            timeZoneIdentifier: timeZone.identifier,
            countryCode: placemark.isoCountryCode,
            source: .manual
        )
    }

    static func displayName(
        locality: String?,
        subAdministrativeArea: String?,
        administrativeArea: String?,
        country: String?,
        fallback: String
    ) -> String {
        let primary = [locality, subAdministrativeArea, administrativeArea, fallback]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? fallback
        var parts = [primary]
        for value in [administrativeArea, country] {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !parts.contains(where: { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }) else { continue }
            parts.append(value)
        }
        return parts.joined(separator: ", ")
    }
}

struct MosqueSearchCandidate: Equatable, Sendable {
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RankedMosqueCandidate: Equatable, Sendable {
    let candidate: MosqueSearchCandidate
    let distance: CLLocationDistance
}

enum MosqueResultRanker {
    static func rank(
        _ candidates: [MosqueSearchCandidate],
        from origin: CLLocationCoordinate2D,
        limit: Int = 5
    ) -> [RankedMosqueCandidate] {
        guard limit > 0 else { return [] }
        var unique: [MosqueSearchCandidate] = []

        for candidate in candidates where CLLocationCoordinate2DIsValid(candidate.coordinate) {
            guard !unique.contains(where: { isDuplicate(candidate, $0) }) else { continue }
            unique.append(candidate)
        }

        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return unique
            .map { candidate in
                RankedMosqueCandidate(
                    candidate: candidate,
                    distance: originLocation.distance(from: CLLocation(
                        latitude: candidate.latitude,
                        longitude: candidate.longitude
                    ))
                )
            }
            .sorted {
                if $0.distance == $1.distance {
                    return $0.candidate.name.localizedCaseInsensitiveCompare($1.candidate.name) == .orderedAscending
                }
                return $0.distance < $1.distance
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func isDuplicate(_ lhs: MosqueSearchCandidate, _ rhs: MosqueSearchCandidate) -> Bool {
        let separation = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude).distance(
            from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        )
        if separation < 40 { return true }
        return canonicalName(lhs.name) == canonicalName(rhs.name) && separation < 150
    }

    private static func canonicalName(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: L10n.locale)
        let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "mosque" && $0 != "masjid" }
        return words.isEmpty ? folded : words.joined(separator: " ")
    }
}

@MainActor
struct MosquePlace: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let mapItem: MKMapItem
}

enum MosqueSearchError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        L10n.string("Nearby mosques could not be loaded. Check your connection and try again.")
    }
}

@MainActor
protocol MosqueSearchProviding: AnyObject {
    func search(near center: CLLocationCoordinate2D, region: MKCoordinateRegion) async throws -> [MosquePlace]
    func cancel()
}

@MainActor
final class AppleMosqueSearchProvider: MosqueSearchProviding {
    private var activeSearches: [MKLocalSearch] = []

    func search(near center: CLLocationCoordinate2D, region: MKCoordinateRegion) async throws -> [MosquePlace] {
        cancel()
        let mosqueSearch = makeSearch(query: "mosque", region: region)
        let masjidSearch = makeSearch(query: "masjid", region: region)
        activeSearches = [mosqueSearch, masjidSearch]
        defer { activeSearches.removeAll() }

        do {
            async let mosqueResponse = mosqueSearch.start()
            async let masjidResponse = masjidSearch.start()
            let (first, second) = try await (mosqueResponse, masjidResponse)
            try Task.checkCancellation()

            let mapItems = first.mapItems + second.mapItems
            let sources = mapItems.map { item in
                MosqueSearchCandidate(
                    name: item.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                        ?? L10n.string("Unnamed Mosque"),
                    address: Self.address(for: item),
                    latitude: item.placemark.coordinate.latitude,
                    longitude: item.placemark.coordinate.longitude
                )
            }
            let ranked = MosqueResultRanker.rank(sources, from: center)
            return ranked.compactMap { result in
                guard let index = sources.firstIndex(of: result.candidate) else { return nil }
                let mapItem = mapItems[index]
                return MosquePlace(
                    id: Self.identifier(for: result.candidate),
                    name: result.candidate.name,
                    address: result.candidate.address,
                    coordinate: result.candidate.coordinate,
                    distance: result.distance,
                    mapItem: mapItem
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw MosqueSearchError.unavailable
        }
    }

    func cancel() {
        activeSearches.forEach { $0.cancel() }
        activeSearches.removeAll()
    }

    private func makeSearch(query: String, region: MKCoordinateRegion) -> MKLocalSearch {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest
        return MKLocalSearch(request: request)
    }

    private static func address(for item: MKMapItem) -> String {
        let title = item.placemark.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty, title.hasPrefix(name) {
            return String(title.dropFirst(name.count)).trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        }
        return title.isEmpty ? L10n.string("Address unavailable") : title
    }

    private static func identifier(for candidate: MosqueSearchCandidate) -> String {
        let latitude = Int((candidate.latitude * 100_000).rounded())
        let longitude = Int((candidate.longitude * 100_000).rounded())
        return "\(candidate.name.lowercased())|\(latitude)|\(longitude)"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

enum NotificationAuthorization: String, Sendable {
    case notDetermined, authorized, denied
}

struct ReminderPreference: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var offsetMinutes: Int = 0
}

enum CharityReminderRepeat: String, Codable, CaseIterable, Identifiable, Sendable {
    case once
    case weekly
    case monthly

    var id: Self { self }

    var title: String {
        switch self {
        case .once: L10n.string("Once")
        case .weekly: L10n.string("Weekly")
        case .monthly: L10n.string("Monthly")
        }
    }
}

struct CharityReminderPreference: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var date: Date = Self.suggestedDate()
    var repeatCycle: CharityReminderRepeat = .monthly

    private enum CodingKeys: String, CodingKey {
        case enabled
        case date
        case repeatCycle
    }

    init(
        enabled: Bool = false,
        date: Date = Self.suggestedDate(),
        repeatCycle: CharityReminderRepeat = .monthly
    ) {
        self.enabled = enabled
        self.date = date
        self.repeatCycle = repeatCycle
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Self.suggestedDate()
        repeatCycle = try container.decodeIfPresent(CharityReminderRepeat.self, forKey: .repeatCycle) ?? .once
    }

    static func suggestedDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

@MainActor
protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    func reconcile(days: [PrayerDay], preferences: [PrayerEvent: ReminderPreference]) async
    func cancel(event: PrayerEvent) async
    func scheduleCharityReminder(_ preference: CharityReminderPreference) async
    func cancelCharityReminder() async
}

enum ReminderIdentifier {
    static func make(event: PrayerEvent, day: LocalDay) -> String {
        "salah.reminder.\(event.rawValue).\(day.key)"
    }
}

struct ReminderCandidate: Equatable, Sendable {
    let triggerDate: Date
    let event: PrayerEvent
    let day: LocalDay
    let timeZone: TimeZone

    var identifier: String { ReminderIdentifier.make(event: event, day: day) }
}

enum ReminderPlan {
    static func make(
        days: [PrayerDay],
        preferences: [PrayerEvent: ReminderPreference],
        now: Date,
        limit: Int = 60
    ) -> [ReminderCandidate] {
        guard limit > 0 else { return [] }
        var candidatesByDay: [LocalDay: [ReminderCandidate]] = [:]
        var identifiers: Set<String> = []
        for day in days.sorted(by: { $0.localDay < $1.localDay }) {
            for event in PrayerEvent.allCases {
                guard let preference = preferences[event], preference.enabled,
                      let eventDate = day.eventDate(event) else { continue }
                let triggerDate = eventDate.addingTimeInterval(TimeInterval(-preference.offsetMinutes * 60))
                let candidate = ReminderCandidate(triggerDate: triggerDate, event: event, day: day.localDay, timeZone: day.timeZone)
                guard triggerDate > now, identifiers.insert(candidate.identifier).inserted else { continue }
                candidatesByDay[candidate.day, default: []].append(candidate)
            }
        }
        var result: [ReminderCandidate] = []
        for day in candidatesByDay.keys.sorted() {
            let group = (candidatesByDay[day] ?? []).sorted { $0.triggerDate < $1.triggerDate }
            guard result.count + group.count <= limit else { break }
            result.append(contentsOf: group)
        }
        return result
    }
}

enum CharityReminderPlan {
    static func make(
        preference: CharityReminderPreference,
        now: Date,
        limit: Int = 12,
        calendar sourceCalendar: Calendar = .current
    ) -> [Date] {
        guard preference.enabled, limit > 0 else { return [] }

        let calendar = sourceCalendar
        let anchor = preference.date
        switch preference.repeatCycle {
        case .once:
            return anchor > now ? [anchor] : []
        case .weekly:
            var candidate = anchor
            while candidate <= now {
                guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: candidate) else { return [] }
                candidate = next
            }
            return (0..<limit).compactMap {
                calendar.date(byAdding: .weekOfYear, value: $0, to: candidate)
            }
        case .monthly:
            let anchorComponents = calendar.dateComponents([.day, .hour, .minute, .second], from: anchor)
            let targetDay = anchorComponents.day ?? 1
            guard let anchorMonthStart = calendar.dateInterval(of: .month, for: anchor)?.start else { return [] }
            var monthOffset = 0
            var dates: [Date] = []
            while dates.count < limit, monthOffset < limit + 1_200 {
                guard let month = calendar.date(byAdding: .month, value: monthOffset, to: anchorMonthStart),
                      let interval = calendar.dateInterval(of: .month, for: month),
                      let dayRange = calendar.range(of: .day, in: .month, for: month) else {
                    break
                }
                var components = calendar.dateComponents([.year, .month], from: interval.start)
                components.day = min(targetDay, dayRange.count)
                components.hour = anchorComponents.hour
                components.minute = anchorComponents.minute
                components.second = anchorComponents.second
                components.timeZone = calendar.timeZone
                if let candidate = calendar.date(from: components), candidate > now {
                    dates.append(candidate)
                }
                monthOffset += 1
            }
            return dates
        }
    }
}

@MainActor
final class LocalNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter
    private let prefix = "salah.reminder."
    private let charityPrefix = "salah.charity-reminder"

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async -> NotificationAuthorization {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return await authorizationStatus()
        } catch {
            return .denied
        }
    }

    func reconcile(days: [PrayerDay], preferences: [PrayerEvent: ReminderPreference]) async {
        let pending = await center.pendingNotificationRequests()
        let owned = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: owned)

        for candidate in ReminderPlan.make(days: days, preferences: preferences, now: .now, limit: 48) {
            let content = UNMutableNotificationContent()
            content.title = candidate.event.title
            content.body = candidate.event == .sahri
                ? L10n.string("Sahri time is approaching.")
                : candidate.event == .iftar
                    ? L10n.string("Iftar time is approaching.")
                    : String(
                        format: L10n.string("It is time for %@."),
                        candidate.event.title
                    )
            content.sound = .default
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = candidate.timeZone
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.triggerDate)
            components.timeZone = candidate.timeZone
            let request = UNNotificationRequest(
                identifier: candidate.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancel(event: PrayerEvent) async {
        let pending = await center.pendingNotificationRequests()
        let eventPrefix = "\(prefix)\(event.rawValue)."
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(eventPrefix) })
    }

    func scheduleCharityReminder(_ preference: CharityReminderPreference) async {
        await cancelCharityReminder()

        let content = UNMutableNotificationContent()
        content.title = L10n.string("Charity reminder")
        content.body = L10n.string("A gentle reminder for the charity you intended to give.")
        content.sound = .default

        let calendar = Calendar.current
        for (index, date) in CharityReminderPlan.make(preference: preference, now: .now).enumerated() {
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            components.timeZone = calendar.timeZone
            let request = UNNotificationRequest(
                identifier: "\(charityPrefix).\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancelCharityReminder() async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(charityPrefix) }
        )
    }
}
