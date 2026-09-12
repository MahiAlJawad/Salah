import Foundation
import UIKit
import WidgetKit

enum WidgetLocalization {
    private static let languageKey = "salah.app-language"

    static var locale: Locale {
        switch UserDefaults(suiteName: WidgetDataStore.groupID)?.string(forKey: languageKey) {
        case "english": Locale(identifier: "en")
        case "bangla": Locale(identifier: "bn")
        default: .autoupdatingCurrent
        }
    }

    private static var selectedBundle: Bundle {
        guard locale.language.languageCode?.identifier == "bn",
              let path = Bundle.main.path(forResource: "bn", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: selectedBundle, locale: locale)
    }

    static func dynamic(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: selectedBundle, locale: locale)
    }
}

enum WidgetPrayerKind: String, Codable, Sendable {
    case fajr, dhuhr, asr, maghrib, isha, sunrise, ishrak, tahajjud

    var isNafl: Bool { self == .ishrak || self == .tahajjud }
    var isObligatory: Bool {
        switch self {
        case .fajr, .dhuhr, .asr, .maghrib, .isha: true
        case .sunrise, .ishrak, .tahajjud: false
        }
    }
}

struct WidgetPrayer: Codable, Identifiable, Sendable {
    let kind: WidgetPrayerKind
    let name: String
    let time: Date
    let end: Date
    let symbolName: String
    let completed: Bool
    let isNext: Bool
    let isCurrent: Bool

    var id: String { kind.rawValue }
    var isNafl: Bool { kind.isNafl }

    init(
        name: String,
        time: Date,
        end: Date,
        symbolName: String,
        completed: Bool,
        isNext: Bool,
        isCurrent: Bool,
        kind: WidgetPrayerKind? = nil
    ) {
        self.kind = kind ?? Self.inferredKind(name: name, symbolName: symbolName)
        self.name = name
        self.time = time
        self.end = end
        self.symbolName = symbolName
        self.completed = completed
        self.isNext = isNext
        self.isCurrent = isCurrent
    }

    enum CodingKeys: String, CodingKey {
        case kind, name, time, end, symbolName, completed, isNext, isCurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        symbolName = try container.decode(String.self, forKey: .symbolName)
        kind = try container.decodeIfPresent(WidgetPrayerKind.self, forKey: .kind)
            ?? Self.inferredKind(name: name, symbolName: symbolName)
        time = try container.decode(Date.self, forKey: .time)
        // `end`/`isCurrent` were added later; snapshots saved before that lack
        // them, so fall back to `time`/`false` rather than failing to decode.
        end = try container.decodeIfPresent(Date.self, forKey: .end) ?? time
        completed = try container.decodeIfPresent(Bool.self, forKey: .completed) ?? false
        isNext = try container.decodeIfPresent(Bool.self, forKey: .isNext) ?? false
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(name, forKey: .name)
        try container.encode(time, forKey: .time)
        try container.encode(end, forKey: .end)
        try container.encode(symbolName, forKey: .symbolName)
        try container.encode(completed, forKey: .completed)
        try container.encode(isNext, forKey: .isNext)
        try container.encode(isCurrent, forKey: .isCurrent)
    }

    private static func inferredKind(name: String, symbolName: String) -> WidgetPrayerKind {
        if name == WidgetLocalization.string("Sunrise") { return .sunrise }
        switch symbolName {
        case "sun.max.fill": return .dhuhr
        case "sun.min.fill": return .asr
        case "sun.horizon.fill": return .maghrib
        case "moon.fill": return .isha
        case "sunrise.fill": return .sunrise
        default: return .fajr
        }
    }
}

struct WidgetDaySchedule: Codable, Sendable {
    let localDayKey: String
    let gregorianSummary: String
    let hijriSummary: String
    let prayers: [WidgetPrayer]
}

struct WidgetSnapshot: Codable, Sendable {
    let updatedAt: Date
    let localDayKey: String
    let gregorianSummary: String
    let hijriSummary: String
    let timeZoneIdentifier: String
    let prayers: [WidgetPrayer]
    let currentPrayer: WidgetPrayer?
    let nextPrayer: WidgetPrayer?
    let tomorrowFajr: WidgetPrayer?
    let nextDay: WidgetDaySchedule?
    /// Additional locally calculated days. Keeping several days in the App
    /// Group lets WidgetKit advance predictable prayer transitions without
    /// requiring the containing app to be opened every day.
    let futureDays: [WidgetDaySchedule]?

    init(
        updatedAt: Date,
        localDayKey: String,
        gregorianSummary: String,
        hijriSummary: String,
        timeZoneIdentifier: String,
        prayers: [WidgetPrayer],
        currentPrayer: WidgetPrayer?,
        nextPrayer: WidgetPrayer?,
        tomorrowFajr: WidgetPrayer?,
        nextDay: WidgetDaySchedule?,
        futureDays: [WidgetDaySchedule]? = nil
    ) {
        self.updatedAt = updatedAt
        self.localDayKey = localDayKey
        self.gregorianSummary = gregorianSummary
        self.hijriSummary = hijriSummary
        self.timeZoneIdentifier = timeZoneIdentifier
        self.prayers = prayers
        self.currentPrayer = currentPrayer
        self.nextPrayer = nextPrayer
        self.tomorrowFajr = tomorrowFajr
        self.nextDay = nextDay
        self.futureDays = futureDays
    }
}

extension WidgetSnapshot {
    private static let ishrakSunriseBuffer: TimeInterval = 20 * 60
    private static let ishrakDhuhrBuffer: TimeInterval = 10 * 60

    /// Mirrors `PrayerTimeline.cardMoment`, using the exact ends calculated by
    /// the app. Old snapshots whose ends are absent still receive a derived
    /// fallback until the app publishes fresh data.
    static func moment(
        at date: Date,
        prayers: [WidgetPrayer],
        tomorrowFajr: WidgetPrayer?,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) -> (current: WidgetPrayer?, next: WidgetPrayer?) {
        let obligatory = prayers
            .filter { $0.kind.isObligatory }
            .sorted { $0.time < $1.time }
        let sunrise = prayers.first { $0.kind == .sunrise }
        let normalizedPrayers = obligatory.enumerated().map { index, prayer in
            Self.normalized(prayer, end: windowEnd(
                for: prayer,
                at: index,
                obligatory: obligatory,
                sunrise: sunrise,
                tomorrowFajr: tomorrowFajr
            ))
        }

        let fajrCandidates = normalizedPrayers.filter { $0.kind == WidgetPrayerKind.fajr }
            + [tomorrowFajr].compactMap { $0 }
        let futureFajr = fajrCandidates
            .filter { $0.time > date }
            .min { $0.time < $1.time }
        if let fajr = futureFajr {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
            let midnight = calendar.startOfDay(for: fajr.time)
            if date >= midnight, date < fajr.time {
                let tahajjud = WidgetPrayer(
                    name: WidgetLocalization.string("Tahajjud"),
                    time: midnight,
                    end: fajr.time,
                    symbolName: "moon.stars.fill",
                    completed: false,
                    isNext: false,
                    isCurrent: true,
                    kind: .tahajjud
                )
                return (tahajjud, flagged(fajr, asNext: true))
            }
        }

        if let sunrise,
           let dhuhr = normalizedPrayers.first(where: { $0.kind == WidgetPrayerKind.dhuhr }) {
            let start = sunrise.time.addingTimeInterval(ishrakSunriseBuffer)
            let end = dhuhr.time.addingTimeInterval(-ishrakDhuhrBuffer)
            if start < end {
                let ishrak = WidgetPrayer(
                    name: WidgetLocalization.string("Ishrak"),
                    time: start,
                    end: end,
                    symbolName: "sunrise.fill",
                    completed: false,
                    isNext: date >= sunrise.time && date < start,
                    isCurrent: date >= start && date < end,
                    kind: .ishrak
                )
                if ishrak.isNext { return (nil, ishrak) }
                if ishrak.isCurrent {
                    return (ishrak, flagged(dhuhr, asNext: true))
                }
            }
        }

        let current = normalizedPrayers.last { $0.time <= date && $0.end > date }
        let next = normalizedPrayers.first { $0.time > date } ?? tomorrowFajr
        return (
            current.map { flagged($0, asCurrent: true) },
            next.map { flagged($0, asNext: true) }
        )
    }

    /// Returns a snapshot only when the supplied date is covered by the saved
    /// schedule. Falling back to an older day's times would be misleading.
    func snapshot(at date: Date) -> WidgetSnapshot? {
        let dateKey = Self.localDayKey(for: date, timeZoneIdentifier: timeZoneIdentifier)
        let schedules = allSchedules
        guard let activeIndex = schedules.firstIndex(where: { $0.localDayKey == dateKey }) else {
            return nil
        }

        let activeSchedule = schedules[activeIndex]
        let followingSchedule = schedules[safe: activeIndex + 1]
        let activePrayers = activeSchedule.prayers
        let activeTomorrowFajr = followingSchedule?.prayers.first { $0.kind == .fajr }
            ?? (activeIndex == 0 ? tomorrowFajr : nil)
        let moment = Self.moment(
            at: date,
            prayers: activePrayers,
            tomorrowFajr: activeTomorrowFajr,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let current = moment.current
        let next = moment.next

        let updatedPrayers = activePrayers.map { prayer in
            WidgetPrayer(
                name: prayer.name,
                time: prayer.time,
                end: prayer.end,
                symbolName: prayer.symbolName,
                completed: prayer.completed,
                isNext: next?.name == prayer.name && next?.time == prayer.time,
                isCurrent: current?.name == prayer.name && current?.time == prayer.time,
                kind: prayer.kind
            )
        }

        return WidgetSnapshot(
            updatedAt: updatedAt,
            localDayKey: activeSchedule.localDayKey,
            gregorianSummary: activeSchedule.gregorianSummary,
            hijriSummary: activeSchedule.hijriSummary,
            timeZoneIdentifier: timeZoneIdentifier,
            prayers: updatedPrayers,
            currentPrayer: current,
            nextPrayer: next,
            tomorrowFajr: activeTomorrowFajr,
            nextDay: followingSchedule,
            futureDays: Array(schedules.dropFirst(activeIndex + 2))
        )
    }

    /// The active obligatory prayer for the inline Lock Screen widget. Its end
    /// comes from the calculated prayer window, rather than a countdown.
    func currentObligatoryPrayer(at date: Date) -> WidgetPrayer? {
        prayers
            .filter { $0.kind.isObligatory && $0.time <= date && $0.end > date }
            .max { $0.time < $1.time }
    }

    /// The next obligatory prayer is used only when no obligatory prayer is
    /// active (for example, in a short gap before Maghrib).
    func nextObligatoryPrayer(after date: Date) -> WidgetPrayer? {
        let upcoming = prayers
            .filter { $0.kind.isObligatory && $0.time > date }
            .min { $0.time < $1.time }
        return upcoming ?? tomorrowFajr
    }

    /// Predictable inline-widget changes: one entry per obligatory prayer
    /// start. This avoids dense end/start entries while providing WidgetKit
    /// enough future data to advance without opening the app each day.
    func inlineTransitionDates(after date: Date, horizon: TimeInterval = 8 * 24 * 60 * 60) -> [Date] {
        let limit = date.addingTimeInterval(horizon)
        return allSchedules
            .flatMap(\.prayers)
            .filter { $0.kind.isObligatory && $0.time > date && $0.time <= limit }
            .map(\.time)
            .sorted()
    }

    func transitionDates(after date: Date, horizon: TimeInterval = 8 * 24 * 60 * 60) -> [Date] {
        let limit = date.addingTimeInterval(horizon)
        let schedules = allSchedules.map(\.prayers)
        var dates = Set<Date>()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

        for schedule in schedules {
            for prayer in schedule {
                dates.insert(prayer.time)
                if prayer.end > prayer.time { dates.insert(prayer.end) }
            }
            if let sunrise = schedule.first(where: { $0.kind == .sunrise }),
               let dhuhr = schedule.first(where: { $0.kind == .dhuhr }) {
                dates.insert(sunrise.time.addingTimeInterval(Self.ishrakSunriseBuffer))
                dates.insert(dhuhr.time.addingTimeInterval(-Self.ishrakDhuhrBuffer))
            }
            if let fajr = schedule.first(where: { $0.kind == .fajr }) {
                dates.insert(calendar.startOfDay(for: fajr.time))
            }
        }
        return dates.filter { $0 > date && $0 <= limit }.sorted()
    }

    private var allSchedules: [WidgetDaySchedule] {
        let currentDay = WidgetDaySchedule(
            localDayKey: localDayKey,
            gregorianSummary: gregorianSummary,
            hijriSummary: hijriSummary,
            prayers: prayers
        )
        let candidates = [currentDay] + [nextDay].compactMap { $0 } + (futureDays ?? [])
        var uniqueSchedules: [String: WidgetDaySchedule] = [:]
        for schedule in candidates {
            uniqueSchedules[schedule.localDayKey] = schedule
        }
        return uniqueSchedules.values.sorted { $0.localDayKey < $1.localDayKey }
    }

    private static func windowEnd(
        for prayer: WidgetPrayer,
        at index: Int,
        obligatory: [WidgetPrayer],
        sunrise: WidgetPrayer?,
        tomorrowFajr: WidgetPrayer?
    ) -> Date {
        if prayer.end > prayer.time { return prayer.end }
        if prayer.kind == .fajr, let sunrise, sunrise.time > prayer.time { return sunrise.time }
        if index + 1 < obligatory.count { return obligatory[index + 1].time }
        return tomorrowFajr?.time ?? prayer.time
    }

    private static func normalized(_ prayer: WidgetPrayer, end: Date) -> WidgetPrayer {
        WidgetPrayer(
            name: prayer.name,
            time: prayer.time,
            end: end,
            symbolName: prayer.symbolName,
            completed: prayer.completed,
            isNext: false,
            isCurrent: false,
            kind: prayer.kind
        )
    }

    private static func flagged(
        _ prayer: WidgetPrayer,
        asCurrent: Bool = false,
        asNext: Bool = false
    ) -> WidgetPrayer {
        WidgetPrayer(
            name: prayer.name,
            time: prayer.time,
            end: prayer.end,
            symbolName: prayer.symbolName,
            completed: prayer.completed,
            isNext: asNext,
            isCurrent: asCurrent,
            kind: prayer.kind
        )
    }

    private static func localDayKey(for date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum WidgetDataStore {
    static let groupID = "group.com.prayer.salah"
    private static let snapshotKey = "salah.widget.snapshot"

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: groupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }

        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "SalahWidgets")
    }

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: snapshotKey) else {
            return nil
        }

        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func updateCompletion(
        kind: WidgetPrayerKind,
        localDayKey: String,
        completed: Bool
    ) {
        guard let snapshot = load() else { return }

        func updating(_ prayer: WidgetPrayer) -> WidgetPrayer {
            guard prayer.kind == kind else { return prayer }
            return WidgetPrayer(
                name: prayer.name,
                time: prayer.time,
                end: prayer.end,
                symbolName: prayer.symbolName,
                completed: completed,
                isNext: prayer.isNext,
                isCurrent: prayer.isCurrent,
                kind: prayer.kind
            )
        }

        func updating(_ schedule: WidgetDaySchedule?) -> WidgetDaySchedule? {
            guard let schedule, schedule.localDayKey == localDayKey else { return schedule }
            return WidgetDaySchedule(
                localDayKey: schedule.localDayKey,
                gregorianSummary: schedule.gregorianSummary,
                hijriSummary: schedule.hijriSummary,
                prayers: schedule.prayers.map(updating)
            )
        }

        let updatesCurrentDay = snapshot.localDayKey == localDayKey
        let updated = WidgetSnapshot(
            updatedAt: .now,
            localDayKey: snapshot.localDayKey,
            gregorianSummary: snapshot.gregorianSummary,
            hijriSummary: snapshot.hijriSummary,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            prayers: updatesCurrentDay ? snapshot.prayers.map(updating) : snapshot.prayers,
            currentPrayer: updatesCurrentDay ? snapshot.currentPrayer.map(updating) : snapshot.currentPrayer,
            nextPrayer: updatesCurrentDay ? snapshot.nextPrayer.map(updating) : snapshot.nextPrayer,
            tomorrowFajr: snapshot.tomorrowFajr,
            nextDay: updating(snapshot.nextDay),
            futureDays: snapshot.futureDays?.map { updating($0) ?? $0 }
        )
        save(updated)
    }
}

struct WidgetPrayerCompletionChange: Codable, Sendable {
    let prayerKind: WidgetPrayerKind
    let localDayKey: String
    let timeZoneIdentifier: String
    let completed: Bool
    let changedAt: Date

    var key: String { "\(localDayKey)|\(prayerKind.rawValue)" }
}

enum WidgetPrayerCompletionStore {
    private static let storageKey = "salah.widget.pending-prayer-completions"

    static func record(
        prayerKind: WidgetPrayerKind,
        localDayKey: String,
        timeZoneIdentifier: String,
        completed: Bool,
        changedAt: Date = .now,
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetDataStore.groupID)
    ) {
        guard let defaults else { return }
        var changes = Dictionary(uniqueKeysWithValues: pendingChanges(defaults: defaults).map { ($0.key, $0) })
        let change = WidgetPrayerCompletionChange(
            prayerKind: prayerKind,
            localDayKey: localDayKey,
            timeZoneIdentifier: timeZoneIdentifier,
            completed: completed,
            changedAt: changedAt
        )
        changes[change.key] = change
        save(Array(changes.values), defaults: defaults)
    }

    static func pendingChanges(
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetDataStore.groupID)
    ) -> [WidgetPrayerCompletionChange] {
        guard let data = defaults?.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([WidgetPrayerCompletionChange].self, from: data)) ?? []
    }

    static func remove(
        keys: Set<String>,
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetDataStore.groupID)
    ) {
        guard let defaults, !keys.isEmpty else { return }
        save(pendingChanges(defaults: defaults).filter { !keys.contains($0.key) }, defaults: defaults)
    }

    static func removeAll(
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetDataStore.groupID)
    ) {
        defaults?.removeObject(forKey: storageKey)
    }

    private static func save(_ changes: [WidgetPrayerCompletionChange], defaults: UserDefaults) {
        guard !changes.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(changes) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

// MARK: - Widget Theme Store

/// Reads the user's theme preference from the shared App Group UserDefaults
/// (written by the main app via `ThemePreferences.save`) and resolves it into
/// concrete RGB values that `WidgetTheme` can turn into SwiftUI `Color`s.
///
/// The widget is always rendered on a dark background, so accent and gradient
/// colours use their dark-mode variants throughout.
enum WidgetThemeStore {
    private static let themeKey = "salah.app-theme"
    private static let customColorKey = "salah.app-custom-theme-color"

    // MARK: Public API

    /// Resolved accent colour as an (r, g, b) tuple in the [0…1] range.
    static var accentRGB: (r: Double, g: Double, b: Double) {
        let defaults = UserDefaults(suiteName: WidgetDataStore.groupID)
        let themeRaw      = defaults?.string(forKey: themeKey)       ?? "greyishBlue"
        let customColorRaw = defaults?.string(forKey: customColorKey) ?? "oceanBlue"
        return resolveAccent(themeRaw: themeRaw, customColorRaw: customColorRaw)
    }

    /// Background gradient stop colours as (start, end) RGB tuples.
    static var backgroundRGB: (start: (Double, Double, Double), end: (Double, Double, Double)) {
        let defaults = UserDefaults(suiteName: WidgetDataStore.groupID)
        let themeRaw       = defaults?.string(forKey: themeKey)       ?? "greyishBlue"
        let customColorRaw = defaults?.string(forKey: customColorKey) ?? "oceanBlue"
        return resolveBackground(themeRaw: themeRaw, customColorRaw: customColorRaw)
    }

    // MARK: Accent resolver

    private static func resolveAccent(themeRaw: String, customColorRaw: String)
        -> (r: Double, g: Double, b: Double)
    {
        switch themeRaw {
        // AccentColor asset (dark variant) — approx. #7490D5
        case "greyishBlue":  return (0.455, 0.565, 0.835)
        // GreenAccent asset (dark variant) — approx. #56DF99
        case "greenishDark": return (0.337, 0.875, 0.600)
        // Slate to Ink Navy accent
        case "slateInkNavy": return (0.345, 0.518, 0.788)
        case "custom":       return accentForCustom(customColorRaw)
        default:             return (0.455, 0.565, 0.835)
        }
    }

    // MARK: Background resolver

    private static func resolveBackground(themeRaw: String, customColorRaw: String)
        -> (start: (Double, Double, Double), end: (Double, Double, Double))
    {
        switch themeRaw {
        case "greyishBlue":
            // Matches existing dark-navy widget background
            return (start: (0.035, 0.075, 0.110), end: (0.020, 0.040, 0.065))
        case "greenishDark":
            // Deep forest-green gradient (mirrors GreenHero / GreenHeroDeep assets)
            return (start: (0.043, 0.098, 0.075), end: (0.020, 0.045, 0.033))
        case "slateInkNavy":
            // Layered slate-to-navy gradient (mirrors heroStart / heroEnd)
            return (start: (0.060, 0.092, 0.160), end: (0.029, 0.054, 0.097))
        case "custom":
            return backgroundForCustom(customColorRaw)
        default:
            return (start: (0.035, 0.075, 0.110), end: (0.020, 0.040, 0.065))
        }
    }

    // MARK: Custom colour helpers

    /// Derives the accent colour for a custom theme, replicating the HSB
    /// formula from `CustomThemeColor.adaptiveColor` in `SharedViews.swift`
    /// (dark variant: saturation * 0.58, brightness 0.86).
    private static func accentForCustom(_ raw: String) -> (r: Double, g: Double, b: Double) {
        let (h, s) = hueAndSaturation(for: raw)
        let uiColor = UIColor(hue: CGFloat(h), saturation: CGFloat(s * 0.58), brightness: 0.86, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b))
    }

    /// Derives gradient stop colours for a custom theme, replicating
    /// `heroStart` / `heroEnd` from `CustomThemeColor.palette` in `SharedViews.swift`.
    private static func backgroundForCustom(_ raw: String)
        -> (start: (Double, Double, Double), end: (Double, Double, Double))
    {
        let (h, s) = hueAndSaturation(for: raw)
        let startUI = UIColor(hue: CGFloat(h), saturation: CGFloat(s * 0.82), brightness: 0.40, alpha: 1)
        let endUI   = UIColor(hue: CGFloat(h), saturation: CGFloat(s * 0.88), brightness: 0.20, alpha: 1)
        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        startUI.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        endUI.getRed(&er, green: &eg, blue: &eb, alpha: &ea)
        return (start: (Double(sr), Double(sg), Double(sb)),
                end:   (Double(er), Double(eg), Double(eb)))
    }

    /// Hue and saturation table — mirrors `CustomThemeColor` private properties
    /// in `SharedViews.swift` exactly so colours stay in sync.
    private static func hueAndSaturation(for raw: String) -> (hue: Double, saturation: Double) {
        switch raw {
        case "oceanBlue":   return (0.590, 0.72)
        case "deepTeal":    return (0.490, 0.64)
        case "emerald":     return (0.400, 0.66)
        case "indigo":      return (0.650, 0.60)
        case "mutedPurple": return (0.750, 0.46)
        case "dustyRose":   return (0.950, 0.46)
        case "terracotta":  return (0.055, 0.64)
        default:            return (0.590, 0.72) // fallback: oceanBlue
        }
    }
}
