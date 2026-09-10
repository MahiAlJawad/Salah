import Foundation

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
