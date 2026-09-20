import CoreData
import Foundation
import OSLog
import SwiftData

@Model
final class PrayerRecord {
    // CloudKit can't enforce unique constraints during concurrent sync; the repository reconciles records by this key.
    /* Example
    Phone A offline: creates 2026-09-19|fajr
    Phone B offline: creates 2026-09-19|fajr
    Both later sync to CloudKit
    */
    var uniquenessKey: String = ""
    var id: UUID = UUID()
    var prayerRawValue: String = ""
    var localDateKey: String = ""
    var timeZoneIdentifier: String = ""
    var isCompleted: Bool = false
    var completedAt: Date?
    var completionSource: String?
    var notes: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

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

enum PersistenceFactory {
    static let cloudKitContainerIdentifier = "iCloud.com.prayer.salah"
    static let modelTypes: [any PersistentModel.Type] = [
        PrayerRecord.self,
        TasbihHistoryRecord.self,
        NaflHistoryRecord.self,
        CharityHistoryRecord.self
    ]

    private static let logger = Logger(subsystem: "com.prayer.salah", category: "Persistence")

    static func makeCloudKitContainer(
        configuration: ModelConfiguration? = nil,
        initializeDevelopmentSchema: Bool = false
    ) throws -> ModelContainer {
        let schema = Schema(modelTypes)
        let configuration = configuration ?? ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )

        #if DEBUG
        if initializeDevelopmentSchema {
            try initializeCloudKitDevelopmentSchema(configuration: configuration, schema: schema)
        }
        #endif

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            logger.info("Loaded SwiftData store with CloudKit container \(cloudKitContainerIdentifier, privacy: .public)")
            return container
        } catch {
            logger.fault("Failed to load SwiftData CloudKit store: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func observeCloudKitEvents() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let operation: String
            switch event.type {
            case .setup: operation = "setup"
            case .import: operation = "import"
            case .export: operation = "export"
            @unknown default: operation = "unknown"
            }
            if let error = event.error {
                logger.error("CloudKit \(operation, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            } else if event.endDate != nil {
                logger.info("CloudKit \(operation, privacy: .public) completed")
            } else {
                logger.debug("CloudKit \(operation, privacy: .public) started")
            }
        }
    }

    #if DEBUG
    private static func initializeCloudKitDevelopmentSchema(
        configuration: ModelConfiguration,
        schema: Schema
    ) throws {
        try autoreleasepool {
            guard let managedObjectModel = NSManagedObjectModel.makeManagedObjectModel(for: modelTypes) else {
                throw CocoaError(.persistentStoreInvalidType)
            }
            let description = NSPersistentStoreDescription(url: configuration.url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
            description.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(
                name: "Salah",
                managedObjectModel: managedObjectModel
            )
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }

            try container.initializeCloudKitSchema()
            for store in container.persistentStoreCoordinator.persistentStores {
                try container.persistentStoreCoordinator.remove(store)
            }
            logger.info("Initialized the CloudKit development schema")
        }
    }
    #endif
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
        context.autosaveEnabled = false
        self.widgetCompletionDefaults = widgetCompletionDefaults
    }

    func records(on day: LocalDay) throws -> [PrayerRecordSnapshot] {
        try synchronizeWidgetCompletions()
        let key = day.key
        try reconcileDuplicates(matching: key, byLocalDate: true)
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
        defer { if context.hasChanges { context.rollback() } }
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
        try reconcileAllDuplicates()
        let descriptor = FetchDescriptor<PrayerRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try context.fetch(descriptor).compactMap(\.snapshot)
    }

    func clearAll() throws {
        defer { if context.hasChanges { context.rollback() } }
        try context.delete(model: PrayerRecord.self)
        try context.save()
        WidgetPrayerCompletionStore.removeAll(defaults: widgetCompletionDefaults)
    }

    private func synchronizeWidgetCompletions() throws {
        defer { if context.hasChanges { context.rollback() } }
        let changes = WidgetPrayerCompletionStore.pendingChanges(defaults: widgetCompletionDefaults)
            .sorted { $0.changedAt < $1.changedAt }
        guard !changes.isEmpty else { return }

        var consumedKeys = Set<String>()
        for change in changes {
            guard let day = LocalDay(stableKey: change.localDayKey) else { continue }
            if let prayer = PrayerType(rawValue: change.prayerKind.rawValue) {
                try upsert(
                    completed: change.completed,
                    prayer: prayer,
                    day: day,
                    timeZoneIdentifier: change.timeZoneIdentifier,
                    source: "widget",
                    changedAt: change.changedAt
                )
            } else if let practice = naflPractice(for: change.prayerKind) {
                let existingMask = try naflMask(on: day)
                let bit = 1 << practice.rawValue
                let mask = change.completed ? existingMask | bit : existingMask & ~bit
                try upsertNafl(NaflDailyRecord(day: day, completedMask: mask, updatedAt: change.changedAt))
            } else {
                continue
            }
            consumedKeys.insert(change.key)
        }
        try context.save()
        WidgetPrayerCompletionStore.remove(keys: consumedKeys, defaults: widgetCompletionDefaults)
    }

    private func naflPractice(for kind: WidgetPrayerKind) -> NaflPractice? {
        switch kind {
        case .tahajjud: .tahajjud
        case .ishrak: .ishrak
        default: nil
        }
    }

    private func naflMask(on day: LocalDay) throws -> Int {
        let key = day.key
        let descriptor = FetchDescriptor<NaflHistoryRecord>(
            predicate: #Predicate { $0.localDateKey == key }
        )
        return try context.fetch(descriptor).first?.completedMask ?? 0
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
        try reconcileDuplicates(matching: uniqueKey)
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

    private func reconcileAllDuplicates() throws {
        let records = try context.fetch(FetchDescriptor<PrayerRecord>())
        for group in Dictionary(grouping: records, by: \.uniquenessKey).values where group.count > 1 {
            removeOlderDuplicates(in: group)
        }
        if context.hasChanges { try context.save() }
    }

    private func reconcileDuplicates(matching value: String, byLocalDate: Bool = false) throws {
        let records: [PrayerRecord]
        if byLocalDate {
            let descriptor = FetchDescriptor<PrayerRecord>(predicate: #Predicate { $0.localDateKey == value })
            records = try context.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<PrayerRecord>(predicate: #Predicate { $0.uniquenessKey == value })
            records = try context.fetch(descriptor)
        }
        for group in Dictionary(grouping: records, by: \.uniquenessKey).values where group.count > 1 {
            removeOlderDuplicates(in: group)
        }
        if context.hasChanges { try context.save() }
    }

    private func removeOlderDuplicates(in records: [PrayerRecord]) {
        guard let winner = records.max(by: { lhs, rhs in
            lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.updatedAt < rhs.updatedAt
        }) else { return }
        for record in records where record !== winner { context.delete(record) }
    }

    private func upsertNafl(_ record: NaflDailyRecord) throws {
        let key = record.day.key
        let descriptor = FetchDescriptor<NaflHistoryRecord>(
            predicate: #Predicate { $0.localDateKey == key }
        )
        if let existing = try context.fetch(descriptor).first {
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
}

@MainActor
final class SwiftDataTrackerHistoryRepository: TrackerHistoryRepository {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
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
        defer { if context.hasChanges { context.rollback() } }
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
        defer { if context.hasChanges { context.rollback() } }
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
        defer { if context.hasChanges { context.rollback() } }
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
        defer { if context.hasChanges { context.rollback() } }
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
        defer { if context.hasChanges { context.rollback() } }
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
        defer { if context.hasChanges { context.rollback() } }
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
