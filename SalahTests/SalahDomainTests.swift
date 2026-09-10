import SwiftData
import XCTest
@testable import Salah

final class SalahDomainTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Dhaka") ?? .gmt
    private let day = LocalDay(year: 2026, month: 7, day: 20)

    func testCurrentAndNextPrayerAcrossDay() throws {
        let today = try fixture(day: day)
        let yesterday = try fixture(day: day.adding(days: -1, in: zone))

        let beforeFajr = try XCTUnwrap(day.date(in: zone, hour: 4, minute: 30))
        let earlyMoment = PrayerTimeline.moment(now: beforeFajr, today: today, previous: yesterday)
        XCTAssertEqual(earlyMoment.current?.prayer, .isha)
        XCTAssertEqual(earlyMoment.next?.prayer, .fajr)

        let duringAsr = try XCTUnwrap(day.date(in: zone, hour: 16, minute: 30))
        let asrMoment = PrayerTimeline.moment(now: duringAsr, today: today, previous: yesterday)
        XCTAssertEqual(asrMoment.current?.prayer, .asr)
        XCTAssertEqual(asrMoment.next?.prayer, .maghrib)
        XCTAssertGreaterThan(asrMoment.progress, 0)

        let duringIsha = try XCTUnwrap(day.date(in: zone, hour: 23, minute: 0))
        XCTAssertEqual(PrayerTimeline.moment(now: duringIsha, today: today, previous: yesterday).current?.prayer, .isha)
    }

    func testPrayerWindowsUseExclusiveEndAndAccessibleDisplayEnd() throws {
        let value = try fixture(day: day).window(for: .fajr)
        let window = try XCTUnwrap(value)
        XCTAssertTrue(window.contains(window.start))
        XCTAssertFalse(window.contains(window.end))
        XCTAssertEqual(window.displayEnd, window.end.addingTimeInterval(-60))
    }

    func testIshaCrossesMidnightAndEndsAtAdjustedSahri() throws {
        let value = try fixture(day: day).window(for: .isha)
        let window = try XCTUnwrap(value)
        XCTAssertGreaterThan(window.end, try XCTUnwrap(day.adding(days: 1, in: zone).date(in: zone, hour: 0)))
        XCTAssertEqual(window.end, try XCTUnwrap(day.adding(days: 1, in: zone).date(in: zone, hour: 4, minute: 57)))
    }

    func testLocalCalculatorPreservesSahriAndIftarSafetyRules() throws {
        let calculator = AdhanPrayerTimesCalculator()
        let query = PrayerTimesQuery(day: day, location: .dhaka, settings: CalculationSettings())
        let calculated = try calculator.calculateDay(query: query, location: .dhaka)
        let fajr = try XCTUnwrap(calculated.window(for: .fajr)?.start)
        XCTAssertEqual(calculated.sahri, fajr.addingTimeInterval(-13 * 60))
        XCTAssertEqual(calculated.iftar, calculated.sunset.addingTimeInterval(3 * 60))
        XCTAssertEqual(calculated.window(for: .maghrib)?.start, calculated.iftar)
        XCTAssertEqual(calculated.methodName, CalculationMethod.karachi.fullTitle)
    }

    func testLocalCalculatorSupportsEveryDisplayedMethod() throws {
        let calculator = AdhanPrayerTimesCalculator()
        for method in CalculationMethod.allCases {
            var settings = CalculationSettings()
            settings.method = method
            let query = PrayerTimesQuery(day: day, location: .dhaka, settings: settings)
            let calculated = try calculator.calculateDay(query: query, location: .dhaka)
            XCTAssertEqual(calculated.windows.count, 5)
            XCTAssertLessThan(try XCTUnwrap(calculated.window(for: .fajr)?.start), calculated.sunrise)
            XCTAssertLessThan(calculated.sunrise, try XCTUnwrap(calculated.window(for: .dhuhr)?.start))
            XCTAssertGreaterThan(try XCTUnwrap(calculated.window(for: .isha)?.end), try XCTUnwrap(calculated.window(for: .isha)?.start))
        }
    }

    func testAutomaticMethodUsesBangladeshKarachiDefault() throws {
        var settings = CalculationSettings()
        settings.method = .automatic
        let query = PrayerTimesQuery(day: day, location: .dhaka, settings: settings)
        let calculated = try AdhanPrayerTimesCalculator().calculateDay(query: query, location: .dhaka)
        XCTAssertEqual(calculated.methodName, CalculationMethod.karachi.fullTitle)
    }

    func testHijriAdjustmentMovesDateLocally() throws {
        let calculator = AdhanPrayerTimesCalculator()
        var baseSettings = CalculationSettings()
        baseSettings.hijriAdjustment = 0
        var adjustedSettings = baseSettings
        adjustedSettings.hijriAdjustment = 1
        let base = try calculator.calculateDay(
            query: PrayerTimesQuery(day: day, location: .dhaka, settings: baseSettings),
            location: .dhaka
        )
        let adjusted = try calculator.calculateDay(
            query: PrayerTimesQuery(day: day, location: .dhaka, settings: adjustedSettings),
            location: .dhaka
        )
        XCTAssertNotEqual(base.hijriSummary, adjusted.hijriSummary)
    }

    func testCacheKeyIncludesEveryTimingInput() {
        let base = PrayerTimesQuery(day: day, location: .dhaka, settings: .init())
        var location = PrayerLocation.dhaka
        location.latitude += 0.001
        XCTAssertNotEqual(base.cacheKey, PrayerTimesQuery(day: day, location: location, settings: .init()).cacheKey)

        var settings = CalculationSettings()
        settings.method = .isna
        XCTAssertNotEqual(base.cacheKey, PrayerTimesQuery(day: day, location: .dhaka, settings: settings).cacheKey)
        settings = CalculationSettings(); settings.madhab = .standard
        XCTAssertNotEqual(base.cacheKey, PrayerTimesQuery(day: day, location: .dhaka, settings: settings).cacheKey)
        settings = CalculationSettings(); settings.hijriAdjustment = 1
        XCTAssertNotEqual(base.cacheKey, PrayerTimesQuery(day: day, location: .dhaka, settings: settings).cacheKey)
        settings = CalculationSettings(); settings.cautionMinutes = 5
        XCTAssertNotEqual(base.cacheKey, PrayerTimesQuery(day: day, location: .dhaka, settings: settings).cacheKey)
    }

    func testCacheFreshnessAndInvalidation() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cache = PrayerTimesCache(fileURL: file, freshness: 10)
        let query = PrayerTimesQuery(day: day, location: .dhaka, settings: .init())
        let value = try fixture(day: day)
        await cache.store(value, for: query, now: Date(timeIntervalSince1970: 100))
        let fresh = await cache.value(for: query, now: Date(timeIntervalSince1970: 105))
        let stale = await cache.value(for: query, now: Date(timeIntervalSince1970: 111))
        XCTAssertEqual(fresh?.isStale, false)
        XCTAssertEqual(stale?.isStale, true)
        await cache.invalidate(signature: query.signature)
        let invalidated = await cache.value(for: query)
        XCTAssertNil(invalidated)
    }

    func testLocalRepositoryCalculatesACompleteMonthWithoutNetwork() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let repository = DefaultPrayerTimesRepository(
            calculator: AdhanPrayerTimesCalculator(),
            cache: PrayerTimesCache(fileURL: file)
        )
        let values = try await repository.month(
            containing: day,
            location: .dhaka,
            settings: .init(),
            policy: .reload
        )
        XCTAssertEqual(values.count, 31)
        XCTAssertTrue(values.allSatisfy { $0.source == .calculated && !$0.isStale })
    }

    @MainActor
    func testSwiftDataRepositoryPreventsDuplicatePrayerDateRecords() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PrayerRecord.self, configurations: configuration)
        let repository = SwiftDataPrayerTrackingRepository(container: container)
        try repository.setCompleted(true, prayer: .fajr, day: day, timeZone: zone, source: "test")
        try repository.setCompleted(true, prayer: .fajr, day: day, timeZone: zone, source: "test")
        XCTAssertEqual(try repository.records(on: day).count, 1)
        try repository.setCompleted(false, prayer: .fajr, day: day, timeZone: zone, source: "undo")
        XCTAssertEqual(try repository.records(on: day).first?.completed, false)
    }

    @MainActor
    func testSwiftDataTrackerHistoryRepositoryPersistsAndUpdatesEveryHistoryType() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: TasbihHistoryRecord.self,
            NaflHistoryRecord.self,
            CharityHistoryRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataTrackerHistoryRepository(container: container)

        try repository.setTasbihCount(3, goal: 33, on: day)
        try repository.incrementTasbih(goal: 33, on: day)
        XCTAssertEqual(try repository.tasbihRecords().count, 1)
        XCTAssertEqual(try repository.tasbihRecord(on: day)?.count, 4)

        try repository.setNaflCompletedMask(0b00001, on: day)
        try repository.setNaflCompletedMask(0b10101, on: day)
        XCTAssertEqual(try repository.naflRecords().count, 1)
        XCTAssertEqual(try repository.naflRecord(on: day)?.completedCount, 3)

        let entry = CharityEntry(amount: 25, date: .now, category: .sadaqah)
        try repository.addCharityEntry(entry)
        var updatedEntry = entry
        updatedEntry.amount = 40
        try repository.addCharityEntry(updatedEntry)
        XCTAssertEqual(try repository.charityEntries().count, 1)
        XCTAssertEqual(try repository.charityEntries().first?.amount, 40)

        try repository.deleteCharityEntries(ids: [entry.id])
        XCTAssertTrue(try repository.charityEntries().isEmpty)
    }

    @MainActor
    func testTrackerHistoryMigrationMovesLegacyJSONOnce() throws {
        let suiteName = "TrackerHistoryMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let tasbih = TasbihDailyRecord(day: day, count: 17, goal: 33, updatedAt: .now)
        let nafl = NaflDailyRecord(day: day, completedMask: 0b00101, updatedAt: .now)
        let charity = CharityEntry(amount: 75, date: .now, category: .education)
        defaults.set(TasbihHistoryLedger.encode([tasbih]), forKey: TasbihHistoryLedger.storageKey)
        defaults.set(NaflHistoryLedger.encode([nafl]), forKey: NaflHistoryLedger.storageKey)
        defaults.set(CharityLedger.encode([charity]), forKey: CharityLedger.storageKey)

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(
            for: TasbihHistoryRecord.self,
            NaflHistoryRecord.self,
            CharityHistoryRecord.self,
            configurations: configuration
        )
        let repository = SwiftDataTrackerHistoryRepository(container: container)

        try TrackerHistoryMigration.migrateIfNeeded(to: repository, defaults: defaults)
        try TrackerHistoryMigration.migrateIfNeeded(to: repository, defaults: defaults)

        XCTAssertEqual(try repository.tasbihRecords().map(\.count), [17])
        XCTAssertEqual(try repository.naflRecords().map(\.completedMask), [0b00101])
        XCTAssertEqual(try repository.charityEntries().map(\.id), [charity.id])
        XCTAssertTrue(defaults.bool(forKey: TrackerHistoryMigration.completionKey))
        XCTAssertNil(defaults.data(forKey: TasbihHistoryLedger.storageKey))
        XCTAssertNil(defaults.data(forKey: NaflHistoryLedger.storageKey))
        XCTAssertNil(defaults.data(forKey: CharityLedger.storageKey))
    }

    @MainActor
    func testAddingTrackerModelsPreservesExistingPrayerStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "tracker.store")

        try autoreleasepool {
            let prayerSchema = Schema([PrayerRecord.self])
            let configuration = ModelConfiguration(
                schema: prayerSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: prayerSchema, configurations: [configuration])
            let repository = SwiftDataPrayerTrackingRepository(container: container)
            try repository.setCompleted(true, prayer: .fajr, day: day, timeZone: zone, source: "test")
        }

        try autoreleasepool {
            let trackerSchema = Schema([
                PrayerRecord.self,
                TasbihHistoryRecord.self,
                NaflHistoryRecord.self,
                CharityHistoryRecord.self
            ])
            let configuration = ModelConfiguration(
                schema: trackerSchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: trackerSchema, configurations: [configuration])
            let prayerRepository = SwiftDataPrayerTrackingRepository(container: container)
            let historyRepository = SwiftDataTrackerHistoryRepository(container: container)

            XCTAssertEqual(try prayerRepository.records(on: day).map(\.prayer), [.fajr])
            try historyRepository.setTasbihCount(1, goal: 33, on: day)
            XCTAssertEqual(try historyRepository.tasbihRecord(on: day)?.count, 1)
        }
    }

    func testStreakAndFirstTrackingDateDenominator() {
        let prior = day.adding(days: -1, in: zone)
        let records = [prior, day].flatMap { date in
            PrayerType.allCases.map { prayer in
                PrayerRecordSnapshot(id: UUID(), prayer: prayer, localDay: date, completed: true, completedAt: .now, source: "test", notes: nil)
            }
        }
        let result = TrackerInsightCalculator.calculate(records: records, today: day, timeZone: zone)
        XCTAssertEqual(result.currentStreak, 2)
        XCTAssertEqual(result.bestStreak, 2)
        XCTAssertEqual(result.possible, 10)
        XCTAssertEqual(result.completionPercentage, 1)
    }

    func testReminderIdentifiersOffsetsOrderingCapAndDuplicatePrevention() throws {
        let first = try fixture(day: day)
        let second = try fixture(day: day.adding(days: 1, in: zone))
        let preferences = Dictionary(uniqueKeysWithValues: PrayerEvent.allCases.map {
            ($0, ReminderPreference(enabled: true, offsetMinutes: 10))
        })
        let now = try XCTUnwrap(day.date(in: zone, hour: 0))
        let plan = ReminderPlan.make(days: [first, first, second], preferences: preferences, now: now, limit: 10)
        XCTAssertEqual(plan.count, 7)
        XCTAssertEqual(Set(plan.map(\.identifier)).count, plan.count)
        XCTAssertEqual(plan, plan.sorted { $0.triggerDate < $1.triggerDate })
        XCTAssertEqual(plan.first?.identifier, "salah.reminder.sahri.2026-07-20")
        XCTAssertEqual(plan.first?.triggerDate, first.sahri.addingTimeInterval(-600))
    }

    func testCharityLedgerPersistsEntriesAndCalculatesMonthTotal() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let julyDate = try XCTUnwrap(day.date(in: zone, hour: 12))
        let augustDate = try XCTUnwrap(day.adding(days: 20, in: zone).date(in: zone, hour: 12))
        let entries = [
            CharityEntry(amount: 25, date: julyDate, category: .sadaqah, recipient: "Food bank"),
            CharityEntry(amount: 40, date: julyDate, category: .education),
            CharityEntry(amount: 100, date: augustDate, category: .emergency)
        ]

        let restored = CharityLedger.decode(CharityLedger.encode(entries))

        XCTAssertEqual(restored, entries)
        XCTAssertEqual(CharityLedger.entries(restored, inMonthContaining: julyDate, calendar: calendar).count, 2)
        XCTAssertEqual(CharityLedger.total(restored, inMonthContaining: julyDate, calendar: calendar), 65)
    }

    func testTasbihHistoryPreservesDailyTotalsAcrossCounterResets() {
        var data = Data()
        data = TasbihHistoryLedger.incrementing(goal: 33, on: day, in: data)
        data = TasbihHistoryLedger.incrementing(goal: 33, on: day, in: data)
        data = TasbihHistoryLedger.incrementing(goal: 33, on: day, in: data)

        let record = TasbihHistoryLedger.decode(data).first
        XCTAssertEqual(record?.day, day)
        XCTAssertEqual(record?.count, 3)
        XCTAssertEqual(record?.goal, 33)
    }

    func testNaflHistoryUpdatesOneStableRecordPerDay() {
        var data = NaflHistoryLedger.recording(mask: 0b00001, on: day, in: Data())
        data = NaflHistoryLedger.recording(mask: 0b10101, on: day, in: data)

        let records = NaflHistoryLedger.decode(data)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.completedCount, 3)
        XCTAssertTrue(records.first?.contains(.tahajjud) == true)
        XCTAssertTrue(records.first?.contains(.morningAdhkar) == true)
        XCTAssertTrue(records.first?.contains(.quran) == true)
    }

    func testCharityReminderDefaultsMonthlyAndMigratesLegacyPreferenceAsOnce() throws {
        struct LegacyPreference: Encodable {
            let enabled: Bool
            let date: Date
        }

        XCTAssertEqual(CharityReminderPreference().repeatCycle, .monthly)

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let data = try JSONEncoder().encode(LegacyPreference(enabled: true, date: date))
        let restored = try JSONDecoder().decode(CharityReminderPreference.self, from: data)

        XCTAssertTrue(restored.enabled)
        XCTAssertEqual(restored.date, date)
        XCTAssertEqual(restored.repeatCycle, .once)
    }

    func testCharityReminderPlanCalculatesWeeklyAndMonthEndDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let weeklyAnchor = try XCTUnwrap(LocalDay(year: 2026, month: 7, day: 20).date(in: zone, hour: 9))
        let weeklyNow = try XCTUnwrap(LocalDay(year: 2026, month: 7, day: 21).date(in: zone, hour: 12))
        let weekly = CharityReminderPlan.make(
            preference: CharityReminderPreference(enabled: true, date: weeklyAnchor, repeatCycle: .weekly),
            now: weeklyNow,
            limit: 2,
            calendar: calendar
        )
        XCTAssertEqual(weekly, [
            try XCTUnwrap(LocalDay(year: 2026, month: 7, day: 27).date(in: zone, hour: 9)),
            try XCTUnwrap(LocalDay(year: 2026, month: 8, day: 3).date(in: zone, hour: 9))
        ])

        let monthEndAnchor = try XCTUnwrap(LocalDay(year: 2028, month: 1, day: 31).date(in: zone, hour: 9))
        let monthEndNow = try XCTUnwrap(LocalDay(year: 2028, month: 1, day: 31).date(in: zone, hour: 10))
        let monthly = CharityReminderPlan.make(
            preference: CharityReminderPreference(enabled: true, date: monthEndAnchor, repeatCycle: .monthly),
            now: monthEndNow,
            limit: 2,
            calendar: calendar
        )
        XCTAssertEqual(monthly, [
            try XCTUnwrap(LocalDay(year: 2028, month: 2, day: 29).date(in: zone, hour: 9)),
            try XCTUnwrap(LocalDay(year: 2028, month: 3, day: 31).date(in: zone, hour: 9))
        ])
    }

    func testCharityCurrencyUsesRegionAndLegacyEntriesReceiveCurrentCurrency() throws {
        struct LegacyEntry: Encodable {
            let id: UUID
            let amount: Double
            let date: Date
            let category: CharityCategory
            let recipient: String
            let note: String
        }

        XCTAssertEqual(CharityCurrency.code(for: Locale(identifier: "bn_BD")), "BDT")
        XCTAssertEqual(CharityCurrency.code(for: Locale(identifier: "en_US")), "USD")

        let legacy = LegacyEntry(
            id: UUID(),
            amount: 50,
            date: .now,
            category: .sadaqah,
            recipient: "",
            note: ""
        )
        let legacyData = try JSONEncoder().encode([legacy])
        XCTAssertTrue(CharityLedger.needsCurrencyMigration(legacyData))

        let restored = CharityLedger.decode(legacyData)
        XCTAssertEqual(restored.first?.currencyCode, CharityCurrency.code())
        XCTAssertFalse(CharityLedger.needsCurrencyMigration(CharityLedger.encode(restored)))
    }

    func testQiblaGeometryFromDhaka() {
        let bearing = QiblaGeometry.bearing(from: .dhaka)
        let distance = QiblaGeometry.distance(from: .dhaka).value
        XCTAssertTrue(275...280 ~= bearing)
        XCTAssertTrue(5_000...5_500 ~= distance)
        XCTAssertEqual(QiblaGeometry.shortestAngle(350), -10, accuracy: 0.001)
    }

    @MainActor
    func testAppearanceAndThemePreferencesPersist() throws {
        let suiteName = "SalahDomainTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initial = AppSettings(defaults: defaults)
        XCTAssertEqual(initial.appearance, .system)
        XCTAssertEqual(initial.theme, .greyishBlue)
        XCTAssertEqual(initial.customThemeColor, .oceanBlue)
        XCTAssertEqual(CustomThemeColor.allCases.count, 7)

        initial.appearance = .dark
        initial.theme = .custom
        initial.customThemeColor = .dustyRose
        initial.charityReminder = CharityReminderPreference(enabled: true, date: Date(timeIntervalSince1970: 1_800_000_000))

        let restored = AppSettings(defaults: defaults)
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(restored.theme, .custom)
        XCTAssertEqual(restored.customThemeColor, .dustyRose)
        XCTAssertEqual(restored.charityReminder, initial.charityReminder)
    }

    @MainActor
    func testSettingsOpenerInvokesInjectedAction() {
        var opened = false
        let opener = SettingsOpener {
            opened = true
        }

        opener()

        XCTAssertTrue(opened)
    }

    func testNearestDistrictUsesCoordinateDistance() throws {
        let districts = [
            District(id: "dhaka", name: "Dhaka", banglaName: "ঢাকা", latitude: 23.7115, longitude: 90.4111),
            District(id: "chattogram", name: "Chattogram", banglaName: "চট্টগ্রাম", latitude: 22.3569, longitude: 91.7832)
        ]
        let nearest = DistrictLoader.nearest(
            to: .init(latitude: 22.34, longitude: 91.82),
            districts: districts
        )
        XCTAssertEqual(try XCTUnwrap(nearest).name, "Chattogram")
    }

    @MainActor
    func testAppRouterSyncSelectedDayToNow() {
        let router = AppRouter(timeZone: zone)
        let yesterday = LocalDay(.now, timeZone: zone).adding(days: -1, in: zone)
        router.selectedDay = yesterday
        XCTAssertEqual(router.selectedDay, yesterday)

        router.syncSelectedDayToNow(timeZone: zone)
        let today = LocalDay(.now, timeZone: zone)
        XCTAssertEqual(router.selectedDay, today)

        // A second call when already on today must not produce a redundant change.
        router.syncSelectedDayToNow(timeZone: zone)
        XCTAssertEqual(router.selectedDay, today)
    }

    func testPrayerMomentAt0012() throws {
        let tomorrow = day.adding(days: 1, in: zone)
        let today = try fixture(day: tomorrow)
        let previous = try fixture(day: day)

        let afterMidnight = try XCTUnwrap(tomorrow.date(in: zone, hour: 0, minute: 12))
        let moment = PrayerTimeline.moment(now: afterMidnight, today: today, previous: previous)

        XCTAssertEqual(moment.current?.prayer, .isha)
        XCTAssertEqual(moment.next?.prayer, .fajr)
        XCTAssertNotEqual(moment.current, today.window(for: .isha))
    }

    func testTodayCardShowsTahajjudFromMidnightUntilFajr() throws {
        let tomorrow = day.adding(days: 1, in: zone)
        let today = try fixture(day: tomorrow)
        let previous = try fixture(day: day)
        let afterMidnight = try XCTUnwrap(tomorrow.date(in: zone, hour: 0, minute: 12))

        let moment = PrayerTimeline.cardMoment(now: afterMidnight, today: today, previous: previous)

        guard case .nafl(let practice, let start, let end) = moment.event else {
            return XCTFail("Expected the Tahajjud card window")
        }
        XCTAssertEqual(practice, .tahajjud)
        XCTAssertEqual(start, try XCTUnwrap(tomorrow.date(in: zone, hour: 0)))
        XCTAssertEqual(end, try XCTUnwrap(tomorrow.date(in: zone, hour: 5, minute: 5)))
        XCTAssertTrue(moment.isCurrent)
    }

    func testTodayCardShowsIshrakAndThenUpcomingDhuhr() throws {
        let today = try fixture(day: day)
        let beforeIshrak = try XCTUnwrap(day.date(in: zone, hour: 6, minute: 25))
        let duringIshrak = try XCTUnwrap(day.date(in: zone, hour: 6, minute: 40))
        let afterIshrak = try XCTUnwrap(day.date(in: zone, hour: 12, minute: 3))

        let upcoming = PrayerTimeline.cardMoment(now: beforeIshrak, today: today, previous: nil)
        guard case .nafl(let upcomingPractice, let start, _) = upcoming.event else {
            return XCTFail("Expected upcoming Ishrak")
        }
        XCTAssertEqual(upcomingPractice, .ishrak)
        XCTAssertEqual(start, try XCTUnwrap(day.date(in: zone, hour: 6, minute: 35)))
        XCTAssertFalse(upcoming.isCurrent)

        let current = PrayerTimeline.cardMoment(now: duringIshrak, today: today, previous: nil)
        guard case .nafl(let currentPractice, _, let end) = current.event else {
            return XCTFail("Expected current Ishrak")
        }
        XCTAssertEqual(currentPractice, .ishrak)
        XCTAssertEqual(end, try XCTUnwrap(day.date(in: zone, hour: 12)))
        XCTAssertTrue(current.isCurrent)

        let next = PrayerTimeline.cardMoment(now: afterIshrak, today: today, previous: nil)
        guard case .obligatory(let window) = next.event else {
            return XCTFail("Expected upcoming Dhuhr")
        }
        XCTAssertEqual(window.prayer, .dhuhr)
        XCTAssertFalse(next.isCurrent)
    }

    func testPreviousDayIshaCarryoverOnlyAppliesBeforeFajr() throws {
        let today = try fixture(day: day)
        let beforeFajr = try XCTUnwrap(day.date(in: zone, hour: 4, minute: 30))
        let atFajr = try XCTUnwrap(day.date(in: zone, hour: 5, minute: 5))

        XCTAssertTrue(PrayerTimeline.isPreviousDayIshaCarryover(now: beforeFajr, today: today))
        XCTAssertFalse(PrayerTimeline.isPreviousDayIshaCarryover(now: atFajr, today: today))
    }

    func testMidnightToFajrWindowOnlyAppliesBeforeFajrOnCurrentLocalDay() throws {
        let today = try fixture(day: day)
        let yesterday = try fixture(day: day.adding(days: -1, in: zone))
        let afterMidnight = try XCTUnwrap(day.date(in: zone, hour: 0, minute: 12))
        let atFajr = try XCTUnwrap(day.date(in: zone, hour: 5, minute: 5))
        let beforeMidnight = try XCTUnwrap(day.adding(days: -1, in: zone).date(in: zone, hour: 23, minute: 59))

        XCTAssertTrue(PrayerTimeline.isMidnightToFajrWindow(now: afterMidnight, today: today))
        XCTAssertFalse(PrayerTimeline.isMidnightToFajrWindow(now: atFajr, today: today))
        XCTAssertFalse(PrayerTimeline.isMidnightToFajrWindow(now: beforeMidnight, today: today))
        XCTAssertFalse(PrayerTimeline.isMidnightToFajrWindow(now: afterMidnight, today: yesterday))
    }

    func testWidgetUsesExactPrayerEndInsteadOfFillingGapToNextPrayer() throws {
        let prayerDay = try fixture(day: day)
        let betweenAsrAndMaghrib = try XCTUnwrap(day.date(in: zone, hour: 18, minute: 31))

        let moment = WidgetSnapshot.moment(
            at: betweenAsrAndMaghrib,
            prayers: widgetPrayers(from: prayerDay),
            tomorrowFajr: nil,
            timeZoneIdentifier: zone.identifier
        )

        XCTAssertNil(moment.current)
        XCTAssertEqual(moment.next?.kind, .maghrib)
    }

    func testWidgetShowsIshrakAsUpcomingAndCurrentLikeTodayCard() throws {
        let prayers = widgetPrayers(from: try fixture(day: day))
        let beforeIshrak = try XCTUnwrap(day.date(in: zone, hour: 6, minute: 25))
        let duringIshrak = try XCTUnwrap(day.date(in: zone, hour: 6, minute: 40))

        let upcoming = WidgetSnapshot.moment(
            at: beforeIshrak,
            prayers: prayers,
            tomorrowFajr: nil,
            timeZoneIdentifier: zone.identifier
        )
        XCTAssertNil(upcoming.current)
        XCTAssertEqual(upcoming.next?.kind, .ishrak)
        XCTAssertEqual(upcoming.next?.time, try XCTUnwrap(day.date(in: zone, hour: 6, minute: 35)))

        let current = WidgetSnapshot.moment(
            at: duringIshrak,
            prayers: prayers,
            tomorrowFajr: nil,
            timeZoneIdentifier: zone.identifier
        )
        XCTAssertEqual(current.current?.kind, .ishrak)
        XCTAssertEqual(current.current?.end, try XCTUnwrap(day.date(in: zone, hour: 12)))
        XCTAssertEqual(current.next?.kind, .dhuhr)
    }

    func testWidgetShowsTahajjudAfterMidnightUntilFajr() throws {
        let tomorrow = day.adding(days: 1, in: zone)
        let nextDay = try fixture(day: tomorrow)
        let afterMidnight = try XCTUnwrap(tomorrow.date(in: zone, hour: 0, minute: 12))
        let nextFajr = try XCTUnwrap(widgetPrayers(from: nextDay).first { $0.kind == .fajr })

        let moment = WidgetSnapshot.moment(
            at: afterMidnight,
            prayers: widgetPrayers(from: try fixture(day: day)),
            tomorrowFajr: nextFajr,
            timeZoneIdentifier: zone.identifier
        )

        XCTAssertEqual(moment.current?.kind, .tahajjud)
        XCTAssertEqual(moment.current?.time, try XCTUnwrap(tomorrow.date(in: zone, hour: 0)))
        XCTAssertEqual(moment.current?.end, try XCTUnwrap(tomorrow.date(in: zone, hour: 5, minute: 5)))
        XCTAssertEqual(moment.next?.kind, .fajr)
    }

    func testWidgetSnapshotHandsOffToNextDayScheduleAfterMidnight() throws {
        let tomorrow = day.adding(days: 1, in: zone)
        let today = try fixture(day: day)
        let nextDay = try fixture(day: tomorrow)
        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            localDayKey: today.localDay.key,
            gregorianSummary: today.gregorianSummary,
            hijriSummary: today.hijriSummary,
            timeZoneIdentifier: zone.identifier,
            prayers: widgetPrayers(from: today),
            currentPrayer: nil,
            nextPrayer: nil,
            tomorrowFajr: widgetPrayers(from: nextDay).first { $0.kind == .fajr },
            nextDay: WidgetDaySchedule(
                localDayKey: nextDay.localDay.key,
                gregorianSummary: "Tuesday, 21 July",
                hijriSummary: "6 Safar 1448",
                prayers: widgetPrayers(from: nextDay)
            )
        )
        let duringDhuhr = try XCTUnwrap(tomorrow.date(in: zone, hour: 13))

        let updated = try XCTUnwrap(snapshot.snapshot(at: duringDhuhr))

        XCTAssertEqual(updated.localDayKey, tomorrow.key)
        XCTAssertEqual(updated.gregorianSummary, "Tuesday, 21 July")
        XCTAssertEqual(updated.currentPrayer?.kind, .dhuhr)
        XCTAssertTrue(updated.prayers.first(where: { $0.kind == .dhuhr })?.isCurrent == true)
    }

    func testWidgetSnapshotUsesFutureScheduleAndInlineSelectsNextObligatoryPrayer() throws {
        let tomorrow = day.adding(days: 1, in: zone)
        let dayAfterTomorrow = tomorrow.adding(days: 1, in: zone)
        let today = try fixture(day: day)
        let nextDay = try fixture(day: tomorrow)
        let futureDay = try fixture(day: dayAfterTomorrow)
        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            localDayKey: today.localDay.key,
            gregorianSummary: today.gregorianSummary,
            hijriSummary: today.hijriSummary,
            timeZoneIdentifier: zone.identifier,
            prayers: widgetPrayers(from: today),
            currentPrayer: nil,
            nextPrayer: nil,
            tomorrowFajr: widgetPrayers(from: nextDay).first { $0.kind == .fajr },
            nextDay: WidgetDaySchedule(
                localDayKey: nextDay.localDay.key,
                gregorianSummary: nextDay.gregorianSummary,
                hijriSummary: nextDay.hijriSummary,
                prayers: widgetPrayers(from: nextDay)
            ),
            futureDays: [
                WidgetDaySchedule(
                    localDayKey: futureDay.localDay.key,
                    gregorianSummary: futureDay.gregorianSummary,
                    hijriSummary: futureDay.hijriSummary,
                    prayers: widgetPrayers(from: futureDay)
                )
            ]
        )
        let duringAsr = try XCTUnwrap(dayAfterTomorrow.date(in: zone, hour: 16, minute: 30))

        let updated = try XCTUnwrap(snapshot.snapshot(at: duringAsr))

        XCTAssertEqual(updated.localDayKey, dayAfterTomorrow.key)
        XCTAssertEqual(updated.nextObligatoryPrayer(after: duringAsr)?.kind, .maghrib)
    }

    @MainActor
    func testRouterTargetsPreviousIshaInCalendar() {
        let router = AppRouter(timeZone: zone)
        router.showPrayerInCalendar(day: day, prayer: .isha)

        XCTAssertEqual(router.selectedTab, .calendar)
        XCTAssertEqual(router.calendarPrayerTarget?.day, day)
        XCTAssertEqual(router.calendarPrayerTarget?.prayer, .isha)
    }

    @MainActor
    func testLanguagePreferencePersistsAndControlsLocalizedModelText() {
        let previousLanguage = LanguagePreferences.current
        defer { LanguagePreferences.current = previousLanguage }

        let suiteName = "SalahDomainTests.language.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)
        settings.language = .bangla

        let district = District(
            id: "47",
            name: "Dhaka",
            banglaName: "ঢাকা",
            latitude: 23.7115253,
            longitude: 90.4111451
        )
        XCTAssertEqual(district.localizedName, "ঢাকা")
        XCTAssertEqual(AppSettings(defaults: defaults).language, .bangla)

        settings.language = .english
        XCTAssertEqual(district.localizedName, "Dhaka")
        XCTAssertEqual(CharityCategory.sadaqah.title, "Sadaqah")
        XCTAssertEqual(CharityCategory.zakat.title, "Zakat")
    }

    private func fixture(day: LocalDay) throws -> PrayerDay {
        func date(_ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(day.date(in: zone, hour: hour, minute: minute))
        }
        let tomorrow = day.adding(days: 1, in: zone)
        return PrayerDay(
            localDay: day,
            gregorianSummary: "Monday, 20 July",
            hijriSummary: "5 Safar 1448",
            timeZoneIdentifier: zone.identifier,
            sunrise: try date(6, 15),
            sunset: try date(18, 30),
            sahri: try date(4, 57),
            iftar: try date(18, 33),
            windows: [
                PrayerWindow(prayer: .fajr, start: try date(5, 5), end: try date(6, 15)),
                PrayerWindow(prayer: .dhuhr, start: try date(12, 10), end: try date(16, 0)),
                PrayerWindow(prayer: .asr, start: try date(16, 0), end: try date(18, 30)),
                PrayerWindow(prayer: .maghrib, start: try date(18, 33), end: try date(20, 0)),
                PrayerWindow(
                    prayer: .isha,
                    start: try date(20, 0),
                    end: try XCTUnwrap(tomorrow.date(in: zone, hour: 4, minute: 57))
                )
            ],
            methodName: CalculationMethod.karachi.fullTitle,
            fetchedAt: .now
        )
    }

    private func widgetPrayers(from day: PrayerDay) -> [WidgetPrayer] {
        let prayers = day.windows.map { window in
            WidgetPrayer(
                name: window.prayer.title,
                time: window.start,
                end: window.end,
                symbolName: window.prayer.symbol,
                completed: false,
                isNext: false,
                isCurrent: false,
                kind: WidgetPrayerKind(rawValue: window.prayer.rawValue)
            )
        }
        let sunrise = WidgetPrayer(
            name: String(localized: "Sunrise"),
            time: day.sunrise,
            end: day.sunrise,
            symbolName: "sunrise.fill",
            completed: false,
            isNext: false,
            isCurrent: false,
            kind: .sunrise
        )
        return prayers.reduce(into: [WidgetPrayer]()) { result, prayer in
            result.append(prayer)
            if prayer.kind == .fajr { result.append(sunrise) }
        }
    }
}
