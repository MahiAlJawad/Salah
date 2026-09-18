import Foundation
import Observation

@MainActor
protocol TrackerHistoryRepository: AnyObject {
    func tasbihRecords() throws -> [TasbihDailyRecord]
    func tasbihRecord(on day: LocalDay) throws -> TasbihDailyRecord?
    func setTasbihCount(_ count: Int, goal: Int, on day: LocalDay) throws
    func incrementTasbih(goal: Int, on day: LocalDay) throws

    func naflRecords() throws -> [NaflDailyRecord]
    func naflRecord(on day: LocalDay) throws -> NaflDailyRecord?
    func setNaflCompletedMask(_ mask: Int, on day: LocalDay) throws

    func charityEntries() throws -> [CharityEntry]
    func addCharityEntry(_ entry: CharityEntry) throws
    func deleteCharityEntries(ids: Set<UUID>) throws

    func importLegacy(
        tasbihRecords: [TasbihDailyRecord],
        naflRecords: [NaflDailyRecord],
        charityEntries: [CharityEntry]
    ) throws
    func clearAll() throws
}

struct TrackerInsights: Equatable, Sendable {
    var currentStreak: Int
    var bestStreak: Int
    var completionPercentage: Double
    var completed: Int
    var possible: Int
    var recent: [PrayerRecordSnapshot]

    static let empty = TrackerInsights(currentStreak: 0, bestStreak: 0, completionPercentage: 0, completed: 0, possible: 0, recent: [])
}

enum TrackerInsightCalculator {
    static func calculate(records: [PrayerRecordSnapshot], today: LocalDay, timeZone: TimeZone) -> TrackerInsights {
        let completed = records.filter(\.completed)
        guard let firstDay = completed.map(\.localDay).min() else { return .empty }
        let grouped = Dictionary(grouping: completed, by: \.localDay)
        var cursor = firstDay
        var fullDays: [LocalDay] = []
        var possible = 0
        while cursor <= today {
            possible += 5
            if Set((grouped[cursor] ?? []).map(\.prayer)).count == 5 { fullDays.append(cursor) }
            cursor = cursor.adding(days: 1, in: timeZone)
        }

        var best = 0
        var run = 0
        var prior: LocalDay?
        for day in fullDays.sorted() {
            if let prior, prior.adding(days: 1, in: timeZone) == day { run += 1 } else { run = 1 }
            best = max(best, run)
            prior = day
        }

        let currentAnchor = Set((grouped[today] ?? []).map(\.prayer)).count == 5 ? today : today.adding(days: -1, in: timeZone)
        var current = 0
        var currentCursor = currentAnchor
        while Set((grouped[currentCursor] ?? []).map(\.prayer)).count == 5 {
            current += 1
            currentCursor = currentCursor.adding(days: -1, in: timeZone)
        }

        return TrackerInsights(
            currentStreak: current,
            bestStreak: best,
            completionPercentage: possible == 0 ? 0 : Double(completed.count) / Double(possible),
            completed: completed.count,
            possible: possible,
            recent: completed.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }.prefix(20).map { $0 }
        )
    }
}

/// Coordinates dated writes and the legacy, resettable today counter. The repositories
/// remain the source of truth; defaults are only imported once, never written back on rollover.
@MainActor
@Observable
final class DatedTrackerCoordinator {
    private let repository: any TrackerHistoryRepository
    private let defaults: UserDefaults
    private let now: () -> Date
    var revision = 0

    init(repository: any TrackerHistoryRepository, defaults: UserDefaults = .standard, now: @escaping () -> Date = { .now }) {
        self.repository = repository
        self.defaults = defaults
        self.now = now
    }

    func today(in zone: TimeZone) -> LocalDay { LocalDay(now(), timeZone: zone) }

    func requireTrackable(_ day: LocalDay, in zone: TimeZone) throws {
        guard day <= today(in: zone) else { throw DatedTrackingError.futureDay }
    }

    func reconcile(in zone: TimeZone) throws {
        let today = today(in: zone)
        let migrationKey = "salah.persistence.dated-defaults.v1"
        if !defaults.bool(forKey: migrationKey) {
            // Finish the original JSON migration before considering scalar defaults.
            try TrackerHistoryMigration.migrateIfNeeded(to: repository, defaults: defaults)
            let tasbihDay = LocalDay(stableKey: defaults.string(forKey: "salah.deeds.tasbih-day") ?? "") ?? today
            let count = defaults.integer(forKey: "salah.deeds.istighfar-count")
            if count > 0, tasbihDay <= today, try repository.tasbihRecord(on: tasbihDay) == nil {
                try repository.setTasbihCount(count, goal: defaults.integer(forKey: "salah.deeds.tasbih-goal"), on: tasbihDay)
            }
            let naflDay = LocalDay(stableKey: defaults.string(forKey: "salah.deeds.good-deeds-day") ?? "") ?? today
            let mask = defaults.integer(forKey: "salah.deeds.good-deeds-mask")
            if mask > 0, naflDay <= today, try repository.naflRecord(on: naflDay) == nil {
                try repository.setNaflCompletedMask(mask, on: naflDay)
            }
            let month = String(today.key.prefix(7))
            if try repository.charityEntries().isEmpty,
               defaults.string(forKey: "salah.deeds.charity-month") == month,
               defaults.integer(forKey: "salah.deeds.charity-total") > 0 {
                try repository.addCharityEntry(CharityEntry(
                    amount: Double(defaults.integer(forKey: "salah.deeds.charity-total")), date: now(),
                    category: .other, currencyCode: defaults.string(forKey: CharityCurrency.storageKey) ?? CharityCurrency.code(),
                    note: L10n.string("Imported monthly total")
                ))
            }
            // Hydrate from saved records, including when stale defaults had the same day.
            defaults.set(try repository.tasbihRecord(on: today)?.count ?? 0, forKey: "salah.deeds.istighfar-count")
            defaults.set(today.key, forKey: "salah.deeds.tasbih-day")
            defaults.set(true, forKey: migrationKey)
        }
        if defaults.string(forKey: "salah.deeds.tasbih-day") != today.key {
            let count = try repository.tasbihRecord(on: today)?.count ?? 0
            defaults.set(count, forKey: "salah.deeds.istighfar-count")
            defaults.set(today.key, forKey: "salah.deeds.tasbih-day")
        }
        let mask = try repository.naflRecord(on: today)?.completedMask ?? 0
        defaults.set(mask, forKey: "salah.deeds.good-deeds-mask")
        defaults.set(today.key, forKey: "salah.deeds.good-deeds-day")
    }

    func replaceTasbih(_ count: Int, on day: LocalDay, in zone: TimeZone) throws {
        try requireTrackable(day, in: zone)
        guard count >= 0 else { throw DatedTrackingError.invalidCount }
        try reconcile(in: zone)
        let goal = try repository.tasbihRecord(on: day)?.goal ?? (day == today(in: zone) ? defaults.integer(forKey: "salah.deeds.tasbih-goal") : 0)
        try repository.setTasbihCount(count, goal: goal, on: day)
        if day == today(in: zone) {
            defaults.set(count, forKey: "salah.deeds.istighfar-count")
        }
        revision += 1
    }

    /// Returns the new session count only after the daily total has been saved.
    func incrementTasbih(goal: Int, in zone: TimeZone) throws -> Int {
        try reconcile(in: zone)
        let day = today(in: zone)
        let count = defaults.integer(forKey: "salah.deeds.istighfar-count")
        guard count < Int.max, try (repository.tasbihRecord(on: day)?.count ?? 0) < Int.max else {
            throw DatedTrackingError.invalidCount
        }
        try repository.incrementTasbih(goal: goal, on: day)
        defaults.set(count + 1, forKey: "salah.deeds.istighfar-count")
        revision += 1
        return count + 1
    }

    func setNaflMask(_ mask: Int, on day: LocalDay, in zone: TimeZone) throws {
        try requireTrackable(day, in: zone)
        try reconcile(in: zone)
        try repository.setNaflCompletedMask(mask, on: day)
        if day == today(in: zone) { defaults.set(mask, forKey: "salah.deeds.good-deeds-mask") }
        revision += 1
    }

    func addGiving(_ entry: CharityEntry, in zone: TimeZone) throws {
        try requireTrackable(LocalDay(entry.date, timeZone: zone), in: zone)
        try reconcile(in: zone)
        try repository.addCharityEntry(entry)
        revision += 1
    }

    func recordsChanged() { revision += 1 }
}

enum DatedTrackingError: LocalizedError {
    case futureDay, invalidCount
    var errorDescription: String? {
        switch self {
        case .futureDay: L10n.string("Future days cannot be recorded.")
        case .invalidCount: L10n.string("Enter a valid nonnegative whole number.")
        }
    }
}
