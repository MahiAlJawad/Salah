import CoreLocation
import Foundation
import Observation
import SwiftData

enum AppLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case system
    case english
    case bangla

    var id: Self { self }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .bangla: Locale(identifier: "bn")
        }
    }

    var selectorTitle: String {
        switch self {
        case .system: L10n.string("System")
        case .english: "English"
        case .bangla: "বাংলা"
        }
    }

    var usesBangla: Bool {
        switch self {
        case .bangla: true
        case .english: false
        case .system: Locale.autoupdatingCurrent.language.languageCode?.identifier == "bn"
        }
    }
}

enum LanguagePreferences {
    private static let key = "salah.app-language"

    static var current: AppLanguage {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: key),
                  let language = AppLanguage(rawValue: rawValue) else { return .system }
            return language
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            UserDefaults(suiteName: WidgetDataStore.groupID)?.set(newValue.rawValue, forKey: key)
        }
    }
}

enum ThemePreferences {
    private static let themeKey = "salah.app-theme"
    private static let customColorKey = "salah.app-custom-theme-color"

    /// Writes the current theme selection to the App Group UserDefaults so
    /// the widget extension can read and render it. Also triggers a widget
    /// timeline reload so the color change is reflected immediately.
    static func save(theme: ThemePreference, customColor: CustomThemeColor) {
        guard let shared = UserDefaults(suiteName: WidgetDataStore.groupID) else { return }
        shared.set(theme.rawValue, forKey: themeKey)
        shared.set(customColor.rawValue, forKey: customColorKey)
    }
}

enum L10n {
    static var locale: Locale { LanguagePreferences.current.locale }
    static var usesBangla: Bool { LanguagePreferences.current.usesBangla }

    /// `String(localized:bundle:locale:)` still resolves the strings table
    /// using the process language. For an in-app override, load the selected
    /// `.lproj` bundle explicitly.
    private static var selectedBundle: Bundle {
        guard usesBangla,
              let path = Bundle.main.path(forResource: "bn", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    static func string(
        _ key: String.LocalizationValue,
        table: String? = nil,
        bundle: Bundle = .main,
        comment: StaticString? = nil
    ) -> String {
        let lookupBundle = bundle.bundleURL == Bundle.main.bundleURL ? selectedBundle : bundle
        return String(localized: key, table: table, bundle: lookupBundle, locale: locale, comment: comment)
    }

    /// Localizes keys that have already passed through a `String`-typed view
    /// model or helper. SwiftUI otherwise renders these values verbatim.
    static func dynamic(_ key: String, table: String? = nil, bundle: Bundle = .main) -> String {
        let lookupBundle = bundle.bundleURL == Bundle.main.bundleURL ? selectedBundle : bundle
        return String(localized: String.LocalizationValue(key), table: table, bundle: lookupBundle, locale: locale)
    }
}

enum AppTab: Hashable, CaseIterable, Identifiable {
    case today, calendar, tracker, qibla, more

    var id: Self { self }

    var title: String {
        switch self {
        case .today: L10n.string("Today")
        case .calendar: L10n.string("Calendar")
        case .tracker: L10n.string("Tracker")
        case .qibla: L10n.string("Qibla")
        case .more: L10n.string("More")
        }
    }

    var systemImage: String {
        switch self {
        case .today: "house.fill"
        case .calendar: "calendar"
        case .tracker: "checklist"
        case .qibla: "location.north.circle.fill"
        case .more: "ellipsis.circle"
        }
    }
}

struct CalendarPrayerTarget: Identifiable, Equatable {
    let id = UUID()
    var day: LocalDay
    var prayer: PrayerType
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var selectedDay: LocalDay
    var calendarPrayerTarget: CalendarPrayerTarget?

    init(timeZone: TimeZone = PrayerLocation.dhaka.timeZone) {
        selectedDay = LocalDay(.now, timeZone: timeZone)
    }

    func showToday(timeZone: TimeZone) {
        selectedDay = LocalDay(.now, timeZone: timeZone)
        selectedTab = .today
    }

    /// Sets selectedDay to the current local day if it differs.
    func syncSelectedDayToNow(timeZone: TimeZone) {
        let today = LocalDay(.now, timeZone: timeZone)
        if selectedDay != today { selectedDay = today }
    }

    func showPrayerInCalendar(day: LocalDay, prayer: PrayerType) {
        calendarPrayerTarget = CalendarPrayerTarget(day: day, prayer: prayer)
        selectedTab = .calendar
    }
}

private struct StoredSettings: Codable {
    var onboardingComplete = false
    var locationEducationSeen = false
    var location = PrayerLocation.dhaka
    var calculation = CalculationSettings()
    var language: AppLanguage?
    var appearance = AppearancePreference.system
    var theme: ThemePreference?
    var customThemeColor: CustomThemeColor?
    var reminders: [String: ReminderPreference] = [:]
    var charityReminder: CharityReminderPreference?
}

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    private let key = "salah.settings.v2"

    var onboardingComplete: Bool { didSet { save() } }
    var locationEducationSeen: Bool { didSet { save() } }
    var location: PrayerLocation { didSet { save() } }
    var calculation: CalculationSettings { didSet { save() } }
    var language: AppLanguage {
        didSet {
            LanguagePreferences.current = language
            save()
        }
    }
    var appearance: AppearancePreference { didSet { save() } }
    var theme: ThemePreference { didSet { save() } }
    var customThemeColor: CustomThemeColor { didSet { save() } }
    private var storedReminders: [String: ReminderPreference] { didSet { save() } }
    var charityReminder: CharityReminderPreference { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing"), (arguments.contains("-reset-state") || arguments.contains("-reset-onboarding")) {
            defaults.removeObject(forKey: key)
        }
        let stored: StoredSettings
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(StoredSettings.self, from: data) {
            stored = decoded
        } else {
            stored = StoredSettings()
        }
        var initialLocation = stored.location
        if initialLocation.source == .automatic,
           initialLocation.name.localizedCaseInsensitiveContains("current location"),
           let nearestDistrict = DistrictLoader.nearest(
               to: CLLocationCoordinate2D(latitude: initialLocation.latitude, longitude: initialLocation.longitude)
           ) {
            initialLocation.name = "\(nearestDistrict.name), Bangladesh"
        }

        let initialLanguage: AppLanguage = if arguments.contains("-ui-testing"), arguments.contains("-bangla-language") {
            .bangla
        } else {
            stored.language ?? .system
        }
        LanguagePreferences.current = initialLanguage
        onboardingComplete = arguments.contains("-ui-testing") && arguments.contains("-onboarding-complete") ? true : stored.onboardingComplete
        locationEducationSeen = stored.locationEducationSeen
        location = initialLocation
        calculation = stored.calculation
        language = initialLanguage
        appearance = stored.appearance
        theme = stored.theme ?? .greyishBlue
        customThemeColor = stored.customThemeColor ?? .oceanBlue
        storedReminders = stored.reminders
        charityReminder = stored.charityReminder ?? CharityReminderPreference()
        if initialLocation != stored.location { save() }
        // Ensure the widget App Group reflects the loaded theme on every launch.
        ThemePreferences.save(theme: theme, customColor: customThemeColor)
    }

    var palette: SalahPalette {
        theme.palette(customColor: customThemeColor)
    }

    var reminders: [PrayerEvent: ReminderPreference] {
        Dictionary(uniqueKeysWithValues: PrayerEvent.allCases.map { ($0, reminder(for: $0)) })
    }

    func reminder(for event: PrayerEvent) -> ReminderPreference {
        storedReminders[event.rawValue] ?? ReminderPreference()
    }

    func setReminder(_ preference: ReminderPreference, for event: PrayerEvent) {
        storedReminders[event.rawValue] = preference
    }

    private func save() {
        let value = StoredSettings(
            onboardingComplete: onboardingComplete,
            locationEducationSeen: locationEducationSeen,
            location: location,
            calculation: calculation,
            language: language,
            appearance: appearance,
            theme: theme,
            customThemeColor: customThemeColor,
            reminders: storedReminders,
            charityReminder: charityReminder
        )
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
        // Mirror theme to the App Group so the widget can pick it up.
        ThemePreferences.save(theme: theme, customColor: customThemeColor)
    }
}

@MainActor
final class InMemoryPrayerTrackingRepository: PrayerTrackingRepository {
    private var values: [String: PrayerRecordSnapshot] = [:]

    func records(on day: LocalDay) throws -> [PrayerRecordSnapshot] {
        values.values.filter { $0.localDay == day }.sorted { $0.prayer.rawValue < $1.prayer.rawValue }
    }

    func completedPrayerTypes(on day: LocalDay) throws -> Set<PrayerType> {
        Set(try records(on: day).filter(\.completed).map(\.prayer))
    }

    func setCompleted(_ completed: Bool, prayer: PrayerType, day: LocalDay, timeZone: TimeZone, source: String) throws {
        let key = "\(day.key)|\(prayer.rawValue)"
        let existingID = values[key]?.id ?? UUID()
        values[key] = PrayerRecordSnapshot(
            id: existingID,
            prayer: prayer,
            localDay: day,
            completed: completed,
            completedAt: completed ? .now : nil,
            source: source,
            notes: values[key]?.notes
        )
    }

    func allRecords() throws -> [PrayerRecordSnapshot] {
        values.values.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func clearAll() throws { values.removeAll() }
}

protocol TrackerSyncCoordinating: Sendable {
    var isAvailable: Bool { get }
}

struct LocalOnlySyncCoordinator: TrackerSyncCoordinating {
    let isAvailable = false
}

@MainActor
@Observable
final class AppContainer {
    let settings: AppSettings
    let router: AppRouter
    let prayerTimesRepository: any PrayerTimesRepository
    let locationProvider: any LocationProviding
    let notificationScheduler: any NotificationScheduling
    let trackingRepository: any PrayerTrackingRepository
    let syncCoordinator: any TrackerSyncCoordinating
    let modelContainer: ModelContainer?
    let districts: [District]

    var localizedLocationName: String {
        let location = settings.location
        guard location.countryCode?.uppercased() == "BD",
              let district = DistrictLoader.nearest(
                  to: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                  districts: districts
              ) else { return location.name }
        return "\(district.localizedName), \(L10n.string("Bangladesh"))"
    }

    init(
        settings: AppSettings? = nil,
        prayerTimesRepository: (any PrayerTimesRepository)? = nil,
        locationProvider: (any LocationProviding)? = nil,
        notificationScheduler: (any NotificationScheduling)? = nil,
        trackingRepository: (any PrayerTrackingRepository)? = nil
    ) {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITesting = arguments.contains("-ui-testing")
        let settingsValue = settings ?? AppSettings()
        self.settings = settingsValue
        router = AppRouter(timeZone: settingsValue.location.timeZone)
        #if DEBUG
        self.locationProvider = locationProvider ?? (isUITesting
            ? UITestLocationProvider(denied: arguments.contains("-location-denied"))
            : CoreLocationProvider())
        self.notificationScheduler = notificationScheduler ?? (isUITesting
            ? UITestNotificationScheduler(status: arguments.contains("-notification-denied")
                ? .denied
                : arguments.contains("-notification-authorized")
                    ? .authorized
                    : .notDetermined)
            : LocalNotificationScheduler())
        #else
        self.locationProvider = locationProvider ?? CoreLocationProvider()
        self.notificationScheduler = notificationScheduler ?? LocalNotificationScheduler()
        #endif
        syncCoordinator = LocalOnlySyncCoordinator()
        districts = DistrictLoader.load()

        #if DEBUG
        if let prayerTimesRepository {
            self.prayerTimesRepository = prayerTimesRepository
        } else if isUITesting {
            self.prayerTimesRepository = UITestPrayerTimesRepository(
                offline: arguments.contains("-offline"),
                slowLoading: arguments.contains("-slow-loading")
            )
        } else {
            self.prayerTimesRepository = DefaultPrayerTimesRepository(
                calculator: AdhanPrayerTimesCalculator(),
                cache: PrayerTimesCache()
            )
        }
        #else
        if let prayerTimesRepository {
            self.prayerTimesRepository = prayerTimesRepository
        } else {
            self.prayerTimesRepository = DefaultPrayerTimesRepository(
                calculator: AdhanPrayerTimesCalculator(),
                cache: PrayerTimesCache()
            )
        }
        #endif

        if let trackingRepository {
            self.trackingRepository = trackingRepository
            modelContainer = nil
        } else if let container = try? ModelContainer(for: PrayerRecord.self) {
            modelContainer = container
            self.trackingRepository = SwiftDataPrayerTrackingRepository(container: container)
        } else {
            modelContainer = nil
            self.trackingRepository = InMemoryPrayerTrackingRepository()
        }
        if isUITesting, arguments.contains("-reset-tracker") {
            try? self.trackingRepository.clearAll()
            UserDefaults.standard.set(0, forKey: "salah.deeds.istighfar-count")
            UserDefaults.standard.set(0, forKey: "salah.deeds.tasbih-goal")
            UserDefaults.standard.removeObject(forKey: "salah.deeds.tasbih-day")
            UserDefaults.standard.removeObject(forKey: TasbihHistoryLedger.storageKey)
            UserDefaults.standard.set(0, forKey: "salah.deeds.good-deeds-mask")
            UserDefaults.standard.removeObject(forKey: "salah.deeds.good-deeds-day")
            UserDefaults.standard.removeObject(forKey: NaflHistoryLedger.storageKey)
            UserDefaults.standard.set(0, forKey: "salah.deeds.charity-total")
            UserDefaults.standard.removeObject(forKey: CharityLedger.storageKey)
        }
    }
}
