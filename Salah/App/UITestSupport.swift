import Foundation

#if DEBUG
actor UITestPrayerTimesRepository: PrayerTimesRepository {
    private let offline: Bool
    private let delay: Duration
    private let unavailable: Bool

    init(offline: Bool, slowLoading: Bool, unavailable: Bool = false) {
        self.offline = offline
        self.unavailable = unavailable
        delay = slowLoading ? .seconds(5) : .milliseconds(700)
    }

    func day(for query: PrayerTimesQuery, location: PrayerLocation, policy: CachePolicy) async throws -> LoadedPrayerDay {
        try await Task.sleep(for: delay)
        if unavailable { throw PrayerDataError.transport("Test prayer service unavailable") }
        let value = makeDay(query.day, location: location, settings: query.settings)
        return LoadedPrayerDay(value: value, source: offline ? .diskCache : .calculated, isStale: offline)
    }

    func month(containing day: LocalDay, location: PrayerLocation, settings: CalculationSettings, policy: CachePolicy) async throws -> [LoadedPrayerDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        let count = day.date(in: location.timeZone).flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 30
        return (1...count).map {
            let value = makeDay(LocalDay(year: day.year, month: day.month, day: $0), location: location, settings: settings)
            return LoadedPrayerDay(value: value, source: offline ? .diskCache : .calculated, isStale: offline)
        }
    }

    func invalidate(signature: String) async { }

    private func makeDay(_ day: LocalDay, location: PrayerLocation, settings: CalculationSettings) -> PrayerDay {
        let zone = location.timeZone
        func date(_ hour: Int, _ minute: Int) -> Date { day.date(in: zone, hour: hour, minute: minute) ?? .now }
        let tomorrow = day.adding(days: 1, in: zone)
        return PrayerDay(
            localDay: day,
            gregorianSummary: PrayerDateFormatting.fullDate(day, timeZone: zone),
            hijriSummary: "5 Safar 1448",
            timeZoneIdentifier: zone.identifier,
            sunrise: date(5, 30),
            sunset: date(18, 30),
            sahri: date(4, 27),
            iftar: date(18, 33),
            windows: [
                PrayerWindow(prayer: .fajr, start: date(4, 30), end: date(5, 30)),
                PrayerWindow(prayer: .dhuhr, start: date(12, 5), end: date(15, 30)),
                PrayerWindow(prayer: .asr, start: date(15, 30), end: date(18, 30)),
                PrayerWindow(prayer: .maghrib, start: date(18, 33), end: date(20, 0)),
                PrayerWindow(prayer: .isha, start: date(20, 0), end: tomorrow.date(in: zone, hour: 4, minute: 27) ?? date(23, 59))
            ],
            methodName: settings.method.title,
            fetchedAt: .now.addingTimeInterval(offline ? -3_600 : 0)
        )
    }
}

@MainActor
final class UITestLocationProvider: LocationProviding {
    let authorization: LocationAuthorization

    init(denied: Bool) {
        authorization = denied ? .denied : .authorized
    }

    func requestCurrentLocation() async throws -> PrayerLocation {
        if authorization == .denied { throw LocationServiceError.denied }
        return PrayerLocation(name: "Dhaka, Bangladesh", latitude: 23.71, longitude: 90.41, timeZoneIdentifier: "Asia/Dhaka", countryCode: "BD", source: .automatic)
    }
}

@MainActor
final class UITestNotificationScheduler: NotificationScheduling {
    private var status: NotificationAuthorization

    init(status: NotificationAuthorization) {
        self.status = status
    }

    func authorizationStatus() async -> NotificationAuthorization { status }
    func requestAuthorization() async -> NotificationAuthorization {
        if status != .denied { status = .authorized }
        return status
    }
    func reconcile(days: [PrayerDay], preferences: [PrayerEvent: ReminderPreference]) async { }
    func cancel(event: PrayerEvent) async { }
    func scheduleCharityReminder(_ preference: CharityReminderPreference) async { }
    func cancelCharityReminder() async { }
}

private extension PrayerTimesQuery {
    var settings: CalculationSettings {
        CalculationSettings(
            method: method,
            madhab: madhab,
            hijriAdjustment: hijriAdjustment,
            cautionMinutes: cautionMinutes,
            timeFormat: .system
        )
    }
}
#endif
