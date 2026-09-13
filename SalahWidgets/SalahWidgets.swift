//
//  SalahWidgets.swift
//  SalahWidgets
//
//  Created by Kazi Tanjim Shakib on 27/7/26.
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), snapshot: nil)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(
            date: .now,
            configuration: configuration,
            snapshot: WidgetDataStore.load()?.snapshot(at: .now)
        )
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let now = Date()
        let stored = WidgetDataStore.load()
        let isInline = context.family == .accessoryInline
        let transitionDates = isInline
            ? stored?.inlineTransitionDates(after: now) ?? []
            : stored?.transitionDates(after: now) ?? []
        let entryDates = [now] + transitionDates.map {
            // For the inline widget, an entry at a prayer's start must select
            // the following prayer as "next". Other families retain their
            // existing post-transition card behavior.
            isInline ? $0 : $0.addingTimeInterval(1)
        }
        let entries = entryDates.map { date in
            SimpleEntry(
                date: date,
                configuration: configuration,
                snapshot: stored?.snapshot(at: date)
            )
        }

        // The saved multi-day schedule covers every predictable transition.
        // WidgetKit may render an entry after its requested date, but it can
        // advance without needing the containing app to be opened each day.
        let policy: TimelineReloadPolicy = transitionDates.isEmpty
            ? .after(now.addingTimeInterval(6 * 60 * 60))
            : .atEnd
        return Timeline(entries: entries, policy: policy)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let snapshot: WidgetSnapshot?
}

struct SalahWidgetsEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                InlineWidgetView(snapshot: entry.snapshot)
            case .systemMedium:
                MediumWidgetView(date: entry.date, snapshot: entry.snapshot)
            default:
                SmallWidgetView(snapshot: entry.snapshot)
            }
        }
        .environment(\.locale, WidgetLocalization.locale)
        .containerBackground(for: .widget) {
            WidgetTheme.background
        }
    }
}

/// Shows the active obligatory prayer with its precomputed end time. The
/// timeline advances at each next-prayer start; WidgetKit ultimately controls
/// when that requested transition is rendered.
private struct InlineWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, let prayer = snapshot.currentPrayer {
            InlinePrayerTime(
                prayer: prayer,
                time: prayer.end,
                timeZoneIdentifier: snapshot.timeZoneIdentifier
            )
        } else if let snapshot, let prayer = snapshot.nextPrayer {
            InlinePrayerTime(
                prayer: prayer,
                time: prayer.time,
                timeZoneIdentifier: snapshot.timeZoneIdentifier
            )
        } else {
            Text(WidgetLocalization.dynamic("Open Salah to refresh times"))
        }
    }
}

private struct InlinePrayerTime: View {
    let prayer: WidgetPrayer
    let time: Date
    let timeZoneIdentifier: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullLabel
                .fixedSize(horizontal: true, vertical: false)
            nameAndTimeLabel
                .fixedSize(horizontal: true, vertical: false)
            iconAndTimeLabel
                .fixedSize(horizontal: true, vertical: false)
        }
        .lineLimit(1)
    }

    private var fullLabel: Text {
        Text(Image(systemName: prayer.symbolName))
            + Text(verbatim: " ")
            + Text(verbatim: prayer.name)
            + Text(verbatim: " ")
            + Text(verbatim: WidgetLocalization.dynamic("Until"))
            + Text(verbatim: " ")
            + Text(verbatim: displayTime)
    }

    private var nameAndTimeLabel: Text {
        Text(Image(systemName: prayer.symbolName))
            + Text(verbatim: " ")
            + Text(verbatim: prayer.name)
            + Text(verbatim: " · ")
            + Text(verbatim: displayTime)
    }

    // Preserve the time, which is the critical information, if a narrow Lock
    // Screen layout cannot accommodate the localized prayer name.
    private var iconAndTimeLabel: Text {
        Text(Image(systemName: prayer.symbolName))
            + Text(verbatim: " ")
            + Text(verbatim: displayTime)
    }

    private var displayTime: String {
        WidgetTimeFormatter.time(time, timezoneIdentifier: timeZoneIdentifier)
    }
}

private enum WidgetTheme {
    /// Resolved at render time from the user's theme stored in the App Group.
    static var accent: Color {
        let rgb = WidgetThemeStore.accentRGB
        return Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    static var background: LinearGradient {
        let bg = WidgetThemeStore.backgroundRGB
        return LinearGradient(
            colors: [
                Color(red: bg.start.0, green: bg.start.1, blue: bg.start.2),
                Color(red: bg.end.0,   green: bg.end.1,   blue: bg.end.2)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // Neutral semantic tones — widget is always dark so these remain white-based.
    static let panel     = Color.white.opacity(0.055)
    static let primary   = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let muted     = Color.white.opacity(0.36)
    static let divider   = Color.white.opacity(0.13)
}

private enum WidgetTimeFormatter {
    static func time(_ date: Date, timezoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = WidgetLocalization.locale
        formatter.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private enum WidgetDateFormatter {
    static func shortGregorianDate(_ localDayKey: String, timezoneIdentifier: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: localDayKey) else { return localDayKey }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = WidgetLocalization.locale
        formatter.timeZone = parser.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter.string(from: date)
    }
}

/// Only the current waqt is highlighted; upcoming prayers retain the baseline
/// color so the active state has a single, unambiguous visual treatment.
private extension WidgetPrayer {
    var mediumRowColor: Color {
        if isCurrent { return WidgetTheme.accent }
        return WidgetTheme.secondary
    }
    var rowWeight: Font.Weight {
        if isCurrent { return .semibold }
        return .regular
    }
}

private extension WidgetSnapshot {
    func fastingEvent(at date: Date) -> (title: String, time: Date, symbolName: String)? {
        guard let maghrib = prayers.first(where: { $0.kind == .maghrib }) else { return nil }

        if date < maghrib.time {
            return (
                WidgetLocalization.dynamic("Iftar"),
                iftar ?? maghrib.time,
                "sun.horizon.fill"
            )
        }

        guard let sahri = nextDay?.sahri else { return nil }
        return (WidgetLocalization.dynamic("Sahri"), sahri, "moon.stars.fill")
    }
}

private struct PrayerCompletionToggle: View {
    let prayer: WidgetPrayer
    let localDayKey: String
    let timeZoneIdentifier: String
    let size: CGFloat

    var body: some View {
        Toggle(
            isOn: prayer.completed,
            intent: SetPrayerCompletionIntent(
                prayerKind: prayer.kind,
                localDayKey: localDayKey,
                timeZoneIdentifier: timeZoneIdentifier,
                completed: !prayer.completed
            )
        ) {
            EmptyView()
        }
        .toggleStyle(PrayerCompletionToggleStyle(size: size))
    }
}

private struct PrayerCompletionToggleStyle: ToggleStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(configuration.isOn ? WidgetTheme.accent : WidgetTheme.secondary)
                .frame(width: size + 8, height: size + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(WidgetLocalization.dynamic(
            configuration.isOn ? "Mark as Not Completed" : "Mark as Completed"
        ))
    }
}

private struct CountdownText: View {
    let isCurrent: Bool
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(WidgetLocalization.dynamic(isCurrent ? "ends in" : "in"))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(date, style: .timer)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(WidgetTheme.accent)
    }
}

private struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, let featured = snapshot.currentPrayer ?? snapshot.nextPrayer {
            let isCurrent = snapshot.currentPrayer != nil
            let countdownDate = isCurrent ? featured.end : featured.time

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(WidgetTheme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(WidgetDateFormatter.shortGregorianDate(
                            snapshot.localDayKey,
                            timezoneIdentifier: snapshot.timeZoneIdentifier
                        ))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(WidgetTheme.secondary)
                            .lineLimit(1)
                        Text(snapshot.hijriSummary)
                            .font(.caption2)
                            .foregroundStyle(WidgetTheme.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 5)

                Spacer()

                HStack(spacing: 9) {
                    Image(systemName: featured.symbolName)
                        .font(.system(size: 30))
                        .foregroundStyle(WidgetTheme.accent)
                        .frame(width: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(featured.name)
                                .font(.system(size: 25, weight: .medium, design: .serif))
                                .foregroundStyle(WidgetTheme.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            if isCurrent, featured.kind.isObligatory {
                                PrayerCompletionToggle(
                                    prayer: featured,
                                    localDayKey: snapshot.localDayKey,
                                    timeZoneIdentifier: snapshot.timeZoneIdentifier,
                                    size: 18
                                )
                            }
                        }
                        CountdownText(isCurrent: isCurrent, date: countdownDate)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                Spacer()

                if let nextPrayer = snapshot.nextPrayer {
                    HStack(spacing: 5) {
                        Image(systemName: nextPrayer.symbolName)
                        Text(nextPrayer.name)
                        Text(WidgetTimeFormatter.time(
                            nextPrayer.time,
                            timezoneIdentifier: snapshot.timeZoneIdentifier
                        ))
                        .monospacedDigit()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(WidgetTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.bottom, 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(12)
        } else {
            Text("Open Salah to load prayer times")
                .font(.caption)
                .foregroundStyle(WidgetTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
        }
    }
}

private struct MediumWidgetView: View {
    let date: Date
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(spacing: 10) {
            if let snapshot, let featured = snapshot.currentPrayer ?? snapshot.nextPrayer {
                let isCurrent = snapshot.currentPrayer != nil
                let countdownDate = isCurrent ? featured.end : featured.time

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundStyle(WidgetTheme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(WidgetDateFormatter.shortGregorianDate(
                                snapshot.localDayKey,
                                timezoneIdentifier: snapshot.timeZoneIdentifier
                            ))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(WidgetTheme.secondary)
                                .lineLimit(1)
                            Text(snapshot.hijriSummary)
                                .font(.caption2)
                                .foregroundStyle(WidgetTheme.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 5)

                    Spacer()

                    HStack(spacing: 9) {
                        Image(systemName: featured.symbolName)
                            .font(.system(size: 30))
                            .foregroundStyle(WidgetTheme.accent)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(featured.name)
                                    .font(.system(size: 25, weight: .medium, design: .serif))
                                    .foregroundStyle(WidgetTheme.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                if isCurrent, featured.kind.isObligatory {
                                    PrayerCompletionToggle(
                                        prayer: featured,
                                        localDayKey: snapshot.localDayKey,
                                        timeZoneIdentifier: snapshot.timeZoneIdentifier,
                                        size: 18
                                    )
                                }
                            }
                            CountdownText(isCurrent: isCurrent, date: countdownDate)
                        }
                    }

                    Spacer()

                    if let fastingEvent = snapshot.fastingEvent(at: date) {
                        HStack(spacing: 5) {
                            Image(systemName: fastingEvent.symbolName)
                            Text(fastingEvent.title)
                            Text(WidgetTimeFormatter.time(
                                fastingEvent.time,
                                timezoneIdentifier: snapshot.timeZoneIdentifier
                            ))
                            .monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetTheme.secondary)
                        .padding(.bottom, 5)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(WidgetTheme.divider)
                    .frame(width: 1)

                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        Spacer()
                        Text("Updated \(WidgetTimeFormatter.time(snapshot.updatedAt, timezoneIdentifier: snapshot.timeZoneIdentifier))")
                        Image(systemName: "arrow.clockwise")
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(WidgetTheme.secondary)
                    .frame(height: 12)
                    .padding(.bottom, 1)

                    ForEach(snapshot.prayers) { prayer in
                        HStack(spacing: 5) {
                            Image(systemName: prayer.symbolName)
                                .font(.system(size: 11))
                                .frame(width: 15)
                                .foregroundStyle(prayer.mediumRowColor)
                            Text(prayer.name)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(prayer.mediumRowColor)
                            Spacer(minLength: 4)
                            Text(WidgetTimeFormatter.time(prayer.time, timezoneIdentifier: snapshot.timeZoneIdentifier))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .foregroundStyle(prayer.mediumRowColor)
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .fontWeight(prayer.rowWeight)
                        .frame(maxWidth: .infinity)
                        .frame(height: 19)

                        if prayer.id != snapshot.prayers.last?.id {
                            Rectangle()
                                .fill(WidgetTheme.divider)
                                .frame(height: 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Open Salah to load prayer times")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(12)
    }
}

struct SalahWidgets: Widget {
    let kind: String = "SalahWidgets"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            SalahWidgetsEntryView(entry: entry)
        }
        .configurationDisplayName("Prayer Times")
        .description("Shows the current prayer and its remaining time.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryInline
        ])
        .contentMarginsDisabled()
    }
}

/// Sample snapshot whose Dhuhr window contains "now", so previews exercise the
/// current-prayer UI (live countdown to the waqt's end).
private func sampleSnapshot(now: Date = .now) -> WidgetSnapshot {
    func minutes(_ value: Double) -> Date { now.addingTimeInterval(value * 60) }
    let dayFormatter = DateFormatter()
    dayFormatter.calendar = Calendar(identifier: .gregorian)
    dayFormatter.locale = Locale(identifier: "en_US_POSIX")
    dayFormatter.timeZone = .current
    dayFormatter.dateFormat = "yyyy-MM-dd"
    let prayers = [
        WidgetPrayer(name: "Fajr", time: minutes(-360), end: minutes(-240), symbolName: "moon.stars.fill", completed: true, isNext: false, isCurrent: false),
        WidgetPrayer(name: "Sunrise", time: minutes(-240), end: minutes(-240), symbolName: "sunrise.fill", completed: false, isNext: false, isCurrent: false),
        WidgetPrayer(name: "Dhuhr", time: minutes(-120), end: minutes(120), symbolName: "sun.max.fill", completed: false, isNext: false, isCurrent: false),
        WidgetPrayer(name: "Asr", time: minutes(150), end: minutes(360), symbolName: "sun.min.fill", completed: false, isNext: false, isCurrent: false),
        WidgetPrayer(name: "Maghrib", time: minutes(370), end: minutes(480), symbolName: "sun.horizon.fill", completed: false, isNext: false, isCurrent: false),
        WidgetPrayer(name: "Isha", time: minutes(490), end: minutes(900), symbolName: "moon.fill", completed: false, isNext: false, isCurrent: false)
    ]
    let tomorrowFajr = WidgetPrayer(name: "Fajr", time: minutes(1440), end: minutes(1560), symbolName: "moon.stars.fill", completed: false, isNext: false, isCurrent: false)
    return WidgetSnapshot(
        updatedAt: now,
        localDayKey: dayFormatter.string(from: now),
        gregorianSummary: "Saturday, 9 August",
        hijriSummary: "15 Safar 1448",
        timeZoneIdentifier: TimeZone.current.identifier,
        prayers: prayers,
        currentPrayer: nil,
        nextPrayer: nil,
        tomorrowFajr: tomorrowFajr,
        nextDay: nil
    )
}

#Preview(as: .systemSmall) {
    SalahWidgets()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: sampleSnapshot().snapshot(at: .now))
}

#Preview(as: .systemMedium) {
    SalahWidgets()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: sampleSnapshot().snapshot(at: .now))
}

#Preview(as: .accessoryInline) {
    SalahWidgets()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: sampleSnapshot().snapshot(at: .now))
}
