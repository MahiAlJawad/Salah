import Foundation
import SwiftData

@Model
final class PrayerRecord {
    @Attribute(.unique) var uniquenessKey: String
    var id: UUID
    var prayerRawValue: String
    var localDateKey: String
    var timeZoneIdentifier: String
    var isCompleted: Bool
    var completedAt: Date?
    var completionSource: String?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        prayer: PrayerType,
        localDay: LocalDay,
        timeZoneIdentifier: String,
        isCompleted: Bool,
        completedAt: Date?,
        completionSource: String?,
        notes: String? = nil
    ) {
        uniquenessKey = "\(localDay.key)|\(prayer.rawValue)"
        self.id = id
        prayerRawValue = prayer.rawValue
        localDateKey = localDay.key
        self.timeZoneIdentifier = timeZoneIdentifier
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.completionSource = completionSource
        self.notes = notes
        createdAt = .now
        updatedAt = .now
    }

    var snapshot: PrayerRecordSnapshot? {
        guard let prayer = PrayerType(rawValue: prayerRawValue),
              let day = LocalDay(stableKey: localDateKey) else { return nil }
        return PrayerRecordSnapshot(
            id: id,
            prayer: prayer,
            localDay: day,
            completed: isCompleted,
            completedAt: completedAt,
            source: completionSource,
            notes: notes
        )
    }
}

@Model
final class TasbihHistoryRecord {
    var id: UUID = UUID()
    var localDateKey: String = ""
    var count: Int = 0
    var goal: Int = 0
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), day: LocalDay, count: Int, goal: Int, updatedAt: Date = .now) {
        self.id = id
        localDateKey = day.key
        self.count = max(0, count)
        self.goal = max(0, goal)
        self.updatedAt = updatedAt
    }

    var snapshot: TasbihDailyRecord? {
        guard let day = LocalDay(stableKey: localDateKey) else { return nil }
        return TasbihDailyRecord(day: day, count: count, goal: goal, updatedAt: updatedAt)
    }
}

@Model
final class NaflHistoryRecord {
    var id: UUID = UUID()
    var localDateKey: String = ""
    var completedMask: Int = 0
    var updatedAt: Date = Date.now

    init(id: UUID = UUID(), day: LocalDay, completedMask: Int, updatedAt: Date = .now) {
        self.id = id
        localDateKey = day.key
        self.completedMask = max(0, completedMask)
        self.updatedAt = updatedAt
    }

    var snapshot: NaflDailyRecord? {
        guard let day = LocalDay(stableKey: localDateKey) else { return nil }
        return NaflDailyRecord(day: day, completedMask: completedMask, updatedAt: updatedAt)
    }
}

@Model
final class CharityHistoryRecord {
    var id: UUID = UUID()
    var amount: Double = 0
    var date: Date = Date.now
    var categoryRawValue: String = CharityCategory.other.rawValue
    var currencyCode: String = "USD"
    var recipient: String = ""
    var note: String = ""

    init(entry: CharityEntry) {
        id = entry.id
        amount = entry.amount
        date = entry.date
        categoryRawValue = entry.category.rawValue
        currencyCode = entry.currencyCode
        recipient = entry.recipient
        note = entry.note
    }

    var snapshot: CharityEntry? {
        guard let category = CharityCategory(rawValue: categoryRawValue) else { return nil }
        return CharityEntry(
            id: id,
            amount: amount,
            date: date,
            category: category,
            currencyCode: currencyCode,
            recipient: recipient,
            note: note
        )
    }
}

extension LocalDay {
    init?(stableKey: String) {
        let parts = stableKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
}

@MainActor
final class SwiftDataPrayerTrackingRepository: PrayerTrackingRepository {
    private let context: ModelContext
    private let widgetCompletionDefaults: UserDefaults?

    init(
        container: ModelContainer,
        widgetCompletionDefaults: UserDefaults? = UserDefaults(suiteName: WidgetDataStore.groupID)
    ) {
        context = ModelContext(container)
        context.autosaveEnabled = true
        self.widgetCompletionDefaults = widgetCompletionDefaults
    }

    func records(on day: LocalDay) throws -> [PrayerRecordSnapshot] {
        try synchronizeWidgetCompletions()
        let key = day.key
        let descriptor = FetchDescriptor<PrayerRecord>(
            predicate: #Predicate { $0.localDateKey == key },
            sortBy: [SortDescriptor(\.prayerRawValue)]
        )
        return try context.fetch(descriptor).compactMap(\.snapshot)
    }

    func completedPrayerTypes(on day: LocalDay) throws -> Set<PrayerType> {
        Set(try records(on: day).filter(\.completed).map(\.prayer))
    }

    func setCompleted(_ completed: Bool, prayer: PrayerType, day: LocalDay, timeZone: TimeZone, source: String) throws {
        try synchronizeWidgetCompletions()
        let now = Date()
        try upsert(
            completed: completed,
            prayer: prayer,
            day: day,
            timeZoneIdentifier: timeZone.identifier,
            source: source,
            changedAt: now
        )
        try context.save()
    }

    func allRecords() throws -> [PrayerRecordSnapshot] {
        try synchronizeWidgetCompletions()
        let descriptor = FetchDescriptor<PrayerRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try context.fetch(descriptor).compactMap(\.snapshot)
    }

    func clearAll() throws {
        try context.delete(model: PrayerRecord.self)
        try context.save()
        WidgetPrayerCompletionStore.removeAll(defaults: widgetCompletionDefaults)
    }

    private func synchronizeWidgetCompletions() throws {
        let changes = WidgetPrayerCompletionStore.pendingChanges(defaults: widgetCompletionDefaults)
            .sorted { $0.changedAt < $1.changedAt }
        guard !changes.isEmpty else { return }

        var consumedKeys = Set<String>()
        for change in changes {
            guard let prayer = PrayerType(rawValue: change.prayerKind.rawValue),
                  let day = LocalDay(stableKey: change.localDayKey) else { continue }
            try upsert(
                completed: change.completed,
                prayer: prayer,
                day: day,
                timeZoneIdentifier: change.timeZoneIdentifier,
                source: "widget",
                changedAt: change.changedAt
            )
            consumedKeys.insert(change.key)
        }
        try context.save()
        WidgetPrayerCompletionStore.remove(keys: consumedKeys, defaults: widgetCompletionDefaults)
    }

    private func upsert(
        completed: Bool,
        prayer: PrayerType,
        day: LocalDay,
        timeZoneIdentifier: String,
        source: String,
        changedAt: Date
    ) throws {
        let uniqueKey = "\(day.key)|\(prayer.rawValue)"
        let descriptor = FetchDescriptor<PrayerRecord>(predicate: #Predicate { $0.uniquenessKey == uniqueKey })
        if let existing = try context.fetch(descriptor).first {
            existing.isCompleted = completed
            existing.completedAt = completed ? changedAt : nil
            existing.completionSource = source
            existing.updatedAt = changedAt
        } else {
            let record = PrayerRecord(
                prayer: prayer,
                localDay: day,
                timeZoneIdentifier: timeZoneIdentifier,
                isCompleted: completed,
                completedAt: completed ? changedAt : nil,
                completionSource: source
            )
            record.updatedAt = changedAt
            context.insert(record)
        }
    }
}

@MainActor
final class SwiftDataTrackerHistoryRepository: TrackerHistoryRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = true
    }

    func tasbihRecords() throws -> [TasbihDailyRecord] {
        let descriptor = FetchDescriptor<TasbihHistoryRecord>(
            sortBy: [SortDescriptor(\.localDateKey)]
        )
        return try context.fetch(descriptor).compactMap(\.snapshot)
    }

    func tasbihRecord(on day: LocalDay) throws -> TasbihDailyRecord? {
        let key = day.key
        let descriptor = FetchDescriptor<TasbihHistoryRecord>(
            predicate: #Predicate { $0.localDateKey == key }
        )
        return try context.fetch(descriptor).first?.snapshot
    }

    func setTasbihCount(_ count: Int, goal: Int, on day: LocalDay) throws {
        try upsertTasbih(TasbihDailyRecord(
            day: day,
            count: max(0, count),
            goal: max(0, goal),
            updatedAt: .now
        ))
        try context.save()
    }

    func incrementTasbih(goal: Int, on day: LocalDay) throws {
        let current = try tasbihRecord(on: day)?.count ?? 0
        try setTasbihCount(current + 1, goal: goal, on: day)
    }

    func naflRecords() throws -> [NaflDailyRecord] {
        let descriptor = FetchDescriptor<NaflHistoryRecord>(
            sortBy: [SortDescriptor(\.localDateKey)]
        )
        return try context.fetch(descriptor).compactMap(\.snapshot)
    }

    func naflRecord(on day: LocalDay) throws -> NaflDailyRecord? {
        let key = day.key
        let descriptor = FetchDescriptor<NaflHistoryRecord>(
            predicate: #Predicate { $0.localDateKey == key }
        )
        return try context.fetch(descriptor).first?.snapshot
    }

    func setNaflCompletedMask(_ mask: Int, on day: LocalDay) throws {
        try upsertNafl(NaflDailyRecord(day: day, completedMask: max(0, mask), updatedAt: .now))
        try context.save()
    }

    func charityEntries() throws -> [CharityEntry] {
        let descriptor = FetchDescriptor<CharityHistoryRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor).compactMap(\.snapshot)
    }

    func addCharityEntry(_ entry: CharityEntry) throws {
        let id = entry.id
        let descriptor = FetchDescriptor<CharityHistoryRecord>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try context.fetch(descriptor).first {
            update(existing, from: entry)
        } else {
            context.insert(CharityHistoryRecord(entry: entry))
        }
        try context.save()
    }

    func deleteCharityEntries(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        for record in try context.fetch(FetchDescriptor<CharityHistoryRecord>()) where ids.contains(record.id) {
            context.delete(record)
        }
        try context.save()
    }

    func importLegacy(
        tasbihRecords: [TasbihDailyRecord],
        naflRecords: [NaflDailyRecord],
        charityEntries: [CharityEntry]
    ) throws {
        for record in tasbihRecords { try upsertTasbih(record, preferringNewest: true) }
        for record in naflRecords { try upsertNafl(record, preferringNewest: true) }
        for entry in charityEntries {
            let id = entry.id
            let descriptor = FetchDescriptor<CharityHistoryRecord>(predicate: #Predicate { $0.id == id })
            if try context.fetch(descriptor).isEmpty {
                context.insert(CharityHistoryRecord(entry: entry))
            }
        }
        try context.save()
    }

    func clearAll() throws {
        try context.delete(model: TasbihHistoryRecord.self)
        try context.delete(model: NaflHistoryRecord.self)
        try context.delete(model: CharityHistoryRecord.self)
        try context.save()
    }

    private func upsertTasbih(_ record: TasbihDailyRecord, preferringNewest: Bool = false) throws {
        let key = record.day.key
        let descriptor = FetchDescriptor<TasbihHistoryRecord>(
            predicate: #Predicate { $0.localDateKey == key }
        )
        if let existing = try context.fetch(descriptor).first {
            guard !preferringNewest || record.updatedAt >= existing.updatedAt else { return }
            existing.count = max(0, record.count)
            existing.goal = max(0, record.goal)
            existing.updatedAt = record.updatedAt
        } else {
            context.insert(TasbihHistoryRecord(
                day: record.day,
                count: record.count,
                goal: record.goal,
                updatedAt: record.updatedAt
            ))
        }
    }

    private func upsertNafl(_ record: NaflDailyRecord, preferringNewest: Bool = false) throws {
        let key = record.day.key
        let descriptor = FetchDescriptor<NaflHistoryRecord>(
            predicate: #Predicate { $0.localDateKey == key }
        )
        if let existing = try context.fetch(descriptor).first {
            guard !preferringNewest || record.updatedAt >= existing.updatedAt else { return }
            existing.completedMask = max(0, record.completedMask)
            existing.updatedAt = record.updatedAt
        } else {
            context.insert(NaflHistoryRecord(
                day: record.day,
                completedMask: record.completedMask,
                updatedAt: record.updatedAt
            ))
        }
    }

    private func update(_ record: CharityHistoryRecord, from entry: CharityEntry) {
        record.amount = entry.amount
        record.date = entry.date
        record.categoryRawValue = entry.category.rawValue
        record.currencyCode = entry.currencyCode
        record.recipient = entry.recipient
        record.note = entry.note
    }
}

@MainActor
final class InMemoryTrackerHistoryRepository: TrackerHistoryRepository {
    private var tasbih: [LocalDay: TasbihDailyRecord] = [:]
    private var nafl: [LocalDay: NaflDailyRecord] = [:]
    private var charity: [UUID: CharityEntry] = [:]

    func tasbihRecords() throws -> [TasbihDailyRecord] { tasbih.values.sorted { $0.day < $1.day } }
    func tasbihRecord(on day: LocalDay) throws -> TasbihDailyRecord? { tasbih[day] }
    func setTasbihCount(_ count: Int, goal: Int, on day: LocalDay) throws {
        tasbih[day] = TasbihDailyRecord(day: day, count: max(0, count), goal: max(0, goal), updatedAt: .now)
    }
    func incrementTasbih(goal: Int, on day: LocalDay) throws {
        try setTasbihCount((tasbih[day]?.count ?? 0) + 1, goal: goal, on: day)
    }

    func naflRecords() throws -> [NaflDailyRecord] { nafl.values.sorted { $0.day < $1.day } }
    func naflRecord(on day: LocalDay) throws -> NaflDailyRecord? { nafl[day] }
    func setNaflCompletedMask(_ mask: Int, on day: LocalDay) throws {
        nafl[day] = NaflDailyRecord(day: day, completedMask: max(0, mask), updatedAt: .now)
    }

    func charityEntries() throws -> [CharityEntry] { charity.values.sorted { $0.date > $1.date } }
    func addCharityEntry(_ entry: CharityEntry) throws { charity[entry.id] = entry }
    func deleteCharityEntries(ids: Set<UUID>) throws {
        for id in ids { charity.removeValue(forKey: id) }
    }

    func importLegacy(
        tasbihRecords: [TasbihDailyRecord],
        naflRecords: [NaflDailyRecord],
        charityEntries: [CharityEntry]
    ) throws {
        for record in tasbihRecords where record.updatedAt >= (tasbih[record.day]?.updatedAt ?? .distantPast) {
            tasbih[record.day] = record
        }
        for record in naflRecords where record.updatedAt >= (nafl[record.day]?.updatedAt ?? .distantPast) {
            nafl[record.day] = record
        }
        for entry in charityEntries where charity[entry.id] == nil { charity[entry.id] = entry }
    }

    func clearAll() throws {
        tasbih.removeAll()
        nafl.removeAll()
        charity.removeAll()
    }
}

@MainActor
enum TrackerHistoryMigration {
    static let completionKey = "salah.persistence.tracker-history-swiftdata.v1"

    static func migrateIfNeeded(
        to repository: any TrackerHistoryRepository,
        defaults: UserDefaults = .standard
    ) throws {
        guard !defaults.bool(forKey: completionKey) else { return }

        let tasbih = TasbihHistoryLedger.decode(defaults.data(forKey: TasbihHistoryLedger.storageKey) ?? Data())
        let nafl = NaflHistoryLedger.decode(defaults.data(forKey: NaflHistoryLedger.storageKey) ?? Data())
        let charity = CharityLedger.decode(defaults.data(forKey: CharityLedger.storageKey) ?? Data())

        try repository.importLegacy(
            tasbihRecords: tasbih,
            naflRecords: nafl,
            charityEntries: charity
        )

        defaults.set(true, forKey: completionKey)
        defaults.removeObject(forKey: TasbihHistoryLedger.storageKey)
        defaults.removeObject(forKey: NaflHistoryLedger.storageKey)
        defaults.removeObject(forKey: CharityLedger.storageKey)
    }
}
