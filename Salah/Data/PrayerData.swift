import Adhan
import Foundation

protocol PrayerTimesCalculating: Sendable {
    func calculateDay(query: PrayerTimesQuery, location: PrayerLocation) throws -> PrayerDay
}

struct AdhanPrayerTimesCalculator: PrayerTimesCalculating {
    /// Preserve the common Imsak convention of ten minutes before Fajr before
    /// applying Salah's user-controlled safety adjustment.
    private let imsakLeadMinutes = 10

    func calculateDay(query: PrayerTimesQuery, location: PrayerLocation) throws -> PrayerDay {
        guard TimeZone(identifier: location.timeZoneIdentifier) != nil else {
            throw PrayerDataError.invalidData("Invalid timezone")
        }

        let method = resolvedMethod(query.method, for: location)
        let coordinates = Coordinates(latitude: query.latitude, longitude: query.longitude)
        let date = dateComponents(for: query.day)
        let tomorrow = query.day.adding(days: 1, in: location.timeZone)
        let tomorrowDate = dateComponents(for: tomorrow)
        var parameters = adhanMethod(for: method).params
        parameters.madhab = query.madhab.resolved(for: location) == .hanafi ? Adhan.Madhab.hanafi : Adhan.Madhab.shafi
        parameters.rounding = .nearest

        guard let times = Adhan.PrayerTimes(
            coordinates: coordinates,
            date: date,
            calculationParameters: parameters
        ), let tomorrowTimes = Adhan.PrayerTimes(
            coordinates: coordinates,
            date: tomorrowDate,
            calculationParameters: parameters
        ) else {
            throw PrayerDataError.invalidData("Prayer times cannot be calculated for this location and date")
        }

        let caution = TimeInterval(query.cautionMinutes * 60)
        let imsakLead = TimeInterval(imsakLeadMinutes * 60)
        let sahri = times.fajr.addingTimeInterval(-imsakLead - caution)
        let iftar = times.maghrib.addingTimeInterval(caution)
        let nextSahri = tomorrowTimes.fajr.addingTimeInterval(-imsakLead - caution)

        return PrayerDay(
            localDay: query.day,
            gregorianSummary: gregorianSummary(for: query.day, timeZone: location.timeZone),
            hijriSummary: try hijriSummary(
                for: query.day,
                adjustment: query.hijriAdjustment,
                timeZone: location.timeZone
            ),
            timeZoneIdentifier: location.timeZoneIdentifier,
            sunrise: times.sunrise,
            sunset: times.maghrib,
            sahri: sahri,
            iftar: iftar,
            windows: [
                PrayerWindow(prayer: .fajr, start: times.fajr, end: times.sunrise),
                PrayerWindow(prayer: .dhuhr, start: times.dhuhr, end: times.asr),
                PrayerWindow(prayer: .asr, start: times.asr, end: times.maghrib),
                PrayerWindow(prayer: .maghrib, start: iftar, end: times.isha),
                PrayerWindow(prayer: .isha, start: times.isha, end: nextSahri)
            ],
            methodName: method.fullTitle,
            fetchedAt: .now
        )
    }

    private func resolvedMethod(_ method: CalculationMethod, for location: PrayerLocation) -> CalculationMethod {
        guard method == .automatic else { return method }
        switch location.countryCode?.uppercased() {
        case "BD", "PK", "IN", "AF": return .karachi
        case "EG": return .egyptian
        case "SA": return .ummAlQura
        case "AE": return .dubai
        case "QA": return .qatar
        case "KW": return .kuwait
        case "SG", "MY", "ID", "BN": return .singapore
        case "TR": return .turkey
        case "IR": return .tehran
        case "US", "CA", "GB": return .moonsightingCommittee
        default: return .muslimWorldLeague
        }
    }

    private func adhanMethod(for method: CalculationMethod) -> Adhan.CalculationMethod {
        switch method {
        case .automatic, .karachi: .karachi
        case .muslimWorldLeague: .muslimWorldLeague
        case .ummAlQura: .ummAlQura
        case .egyptian: .egyptian
        case .isna: .northAmerica
        case .dubai: .dubai
        case .qatar: .qatar
        case .kuwait: .kuwait
        case .singapore: .singapore
        case .turkey: .turkey
        case .tehran: .tehran
        case .moonsightingCommittee: .moonsightingCommittee
        }
    }

    private func dateComponents(for day: LocalDay) -> DateComponents {
        DateComponents(calendar: Calendar(identifier: .gregorian), year: day.year, month: day.month, day: day.day)
    }

    private func gregorianSummary(for day: LocalDay, timeZone: TimeZone) -> String {
        guard let date = day.date(in: timeZone, hour: 12) else { return day.key }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = L10n.locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEEE d MMMM")
        return formatter.string(from: date)
    }

    private func hijriSummary(for day: LocalDay, adjustment: Int, timeZone: TimeZone) throws -> String {
        guard let date = day.date(in: timeZone, hour: 12) else {
            throw PrayerDataError.invalidData("Invalid Gregorian date")
        }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        guard let adjustedDate = gregorian.date(byAdding: .day, value: adjustment, to: date) else {
            throw PrayerDataError.invalidData("Invalid Hijri adjustment")
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .islamicUmmAlQura)
        formatter.locale = L10n.locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y")
        return formatter.string(from: adjustedDate)
    }
}

private struct PrayerCacheEntry: Codable, Sendable {
    var query: PrayerTimesQuery
    var day: PrayerDay
    var storedAt: Date
}

private struct PrayerCacheFile: Codable {
    var entries: [String: PrayerCacheEntry]
}

actor PrayerTimesCache {
    struct Hit: Sendable {
        var day: PrayerDay
        var source: PrayerDataSource
        var isStale: Bool
    }

    private var memory: [String: PrayerCacheEntry] = [:]
    private var disk: [String: PrayerCacheEntry] = [:]
    private let fileURL: URL
    private let freshness: TimeInterval
    private let maxEntries = 760

    init(
        fileManager: FileManager = .default,
        fileURL overrideFileURL: URL? = nil,
        freshness: TimeInterval = 30 * 24 * 60 * 60
    ) {
        self.freshness = freshness
        if let overrideFileURL {
            fileURL = overrideFileURL
            if let data = try? Data(contentsOf: overrideFileURL),
               let decoded = try? JSONDecoder().decode(PrayerCacheFile.self, from: data) {
                disk = decoded.entries
            }
            return
        }
        let support = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory
        let directory = support.appending(path: "Salah", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        fileURL = directory.appending(path: "PrayerTimesCache-v3.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PrayerCacheFile.self, from: data) {
            disk = decoded.entries
        }
    }

    func value(for query: PrayerTimesQuery, now: Date = .now) -> Hit? {
        if let entry = memory[query.cacheKey] {
            return Hit(day: entry.day, source: .memoryCache, isStale: now.timeIntervalSince(entry.storedAt) > freshness)
        }
        if let entry = disk[query.cacheKey] {
            memory[query.cacheKey] = entry
            return Hit(day: entry.day, source: .diskCache, isStale: now.timeIntervalSince(entry.storedAt) > freshness)
        }
        return nil
    }

    func store(_ day: PrayerDay, for query: PrayerTimesQuery, now: Date = .now) {
        let entry = PrayerCacheEntry(query: query, day: day, storedAt: now)
        memory[query.cacheKey] = entry
        disk[query.cacheKey] = entry
        prune()
        persist()
    }

    func invalidate(signature: String) {
        memory = memory.filter { $0.value.query.signature != signature }
        disk = disk.filter { $0.value.query.signature != signature }
        persist()
    }

    private func prune() {
        guard disk.count > maxEntries else { return }
        let retained = disk.values.sorted { $0.storedAt > $1.storedAt }.prefix(maxEntries)
        disk = Dictionary(uniqueKeysWithValues: retained.map { ($0.query.cacheKey, $0) })
        memory = memory.filter { disk[$0.key] != nil }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(PrayerCacheFile(entries: disk)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

actor DefaultPrayerTimesRepository: PrayerTimesRepository {
    private let calculator: any PrayerTimesCalculating
    private let cache: PrayerTimesCache
    private var inFlight: [String: Task<PrayerDay, Error>] = [:]
    private var inFlightMonths: [String: Task<[PrayerDay], Error>] = [:]

    init(calculator: any PrayerTimesCalculating, cache: PrayerTimesCache) {
        self.calculator = calculator
        self.cache = cache
    }

    func day(for query: PrayerTimesQuery, location: PrayerLocation, policy: CachePolicy) async throws -> LoadedPrayerDay {
        let cached = await cache.value(for: query)
        if policy == .cacheFirst, let cached, !cached.isStale {
            return LoadedPrayerDay(value: cached.day, source: cached.source, isStale: false)
        }

        do {
            let value = try await calculatedDay(for: query, location: location)
            return LoadedPrayerDay(value: value, source: .calculated, isStale: false)
        } catch {
            if let cached {
                return LoadedPrayerDay(value: cached.day, source: cached.source, isStale: true)
            }
            throw error
        }
    }

    func month(containing day: LocalDay, location: PrayerLocation, settings: CalculationSettings, policy: CachePolicy) async throws -> [LoadedPrayerDay] {
        let expectedDays = daysInMonth(containing: day, timeZone: location.timeZone)
        var cachedValues: [LoadedPrayerDay] = []
        for localDay in expectedDays {
            let query = PrayerTimesQuery(day: localDay, location: location, settings: settings)
            if let hit = await cache.value(for: query) {
                cachedValues.append(LoadedPrayerDay(value: hit.day, source: hit.source, isStale: hit.isStale))
            }
        }
        if policy == .cacheFirst, cachedValues.count == expectedDays.count, cachedValues.allSatisfy({ !$0.isStale }) {
            return cachedValues.sorted { $0.value.localDay < $1.value.localDay }
        }

        do {
            let prayerDays = try await calculatedMonth(containing: day, location: location, settings: settings)
            var loaded: [LoadedPrayerDay] = []
            for prayerDay in prayerDays {
                let query = PrayerTimesQuery(day: prayerDay.localDay, location: location, settings: settings)
                await cache.store(prayerDay, for: query)
                loaded.append(LoadedPrayerDay(value: prayerDay, source: .calculated, isStale: false))
            }
            return loaded.sorted { $0.value.localDay < $1.value.localDay }
        } catch {
            if !cachedValues.isEmpty {
                return cachedValues.map { LoadedPrayerDay(value: $0.value, source: $0.source, isStale: true) }
                    .sorted { $0.value.localDay < $1.value.localDay }
            }
            throw error
        }
    }

    func invalidate(signature: String) async {
        await cache.invalidate(signature: signature)
    }

    private func calculatedDay(for query: PrayerTimesQuery, location: PrayerLocation) async throws -> PrayerDay {
        if let task = inFlight[query.cacheKey] { return try await task.value }
        let calculator = self.calculator
        let cache = self.cache
        let task = Task<PrayerDay, Error> {
            try calculator.calculateDay(query: query, location: location)
        }
        inFlight[query.cacheKey] = task
        defer { inFlight[query.cacheKey] = nil }
        let value = try await task.value
        await cache.store(value, for: query)
        return value
    }

    private func calculatedMonth(
        containing day: LocalDay,
        location: PrayerLocation,
        settings: CalculationSettings
    ) async throws -> [PrayerDay] {
        let key = "\(day.year)-\(day.month)|\(PrayerTimesQuery(day: day, location: location, settings: settings).signature)"
        if let task = inFlightMonths[key] { return try await task.value }
        let calculator = self.calculator
        let expectedDays = daysInMonth(containing: day, timeZone: location.timeZone)
        let task = Task<[PrayerDay], Error> {
            try expectedDays.map { localDay in
                let query = PrayerTimesQuery(day: localDay, location: location, settings: settings)
                return try calculator.calculateDay(query: query, location: location)
            }
        }
        inFlightMonths[key] = task
        defer { inFlightMonths[key] = nil }
        return try await task.value
    }

    private func daysInMonth(containing day: LocalDay, timeZone: TimeZone) -> [LocalDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = day.date(in: timeZone), let range = calendar.range(of: .day, in: .month, for: date) else { return [day] }
        return range.map { LocalDay(year: day.year, month: day.month, day: $0) }
    }
}
