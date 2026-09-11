//
//  SalahWidgets.swift
//  SalahWidgets
//
//  Created by Kazi Tanjim Shakib on 27/7/26.
//

import WidgetKit
import SwiftUI

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
                InlineWidgetView(date: entry.date, snapshot: entry.snapshot)
            case .systemMedium:
                MediumWidgetView(snapshot: entry.snapshot)
            case .systemLarge:
                LargeWidgetView(snapshot: entry.snapshot)
            default:
                SmallWidgetView(date: entry.date, snapshot: entry.snapshot)
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
    let date: Date
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, let prayer = snapshot.currentObligatoryPrayer(at: date) {
            InlinePrayerTime(
                prayer: prayer,
                time: prayer.end,
                timeZoneIdentifier: snapshot.timeZoneIdentifier
            )
        } else if let snapshot, let prayer = snapshot.nextObligatoryPrayer(after: date) {
            // There is no active obligatory waqt in short gaps such as the
            // period after Asr ends and before Maghrib begins. Show the next
            // start time rather than incorrectly extending the prior prayer.
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

/// Row highlighting helpers. The current waqt is the strongest; the next waqt
/// is secondary; everything else uses the view's baseline color.
private extension WidgetPrayer {
    var mediumRowColor: Color {
        if isCurrent { return WidgetTheme.accent }
        if isNext { return WidgetTheme.accent.opacity(0.6) }
        return WidgetTheme.secondary
    }
    var largeRowColor: Color {
        if isCurrent { return WidgetTheme.accent }
        if isNext { return WidgetTheme.accent.opacity(0.6) }
        return WidgetTheme.primary
    }
    var largeIconColor: Color {
        if isCurrent { return WidgetTheme.accent }
        if isNext { return WidgetTheme.accent.opacity(0.6) }
        return WidgetTheme.secondary
    }
    var rowWeight: Font.Weight {
        if isCurrent { return .semibold }
        if isNext { return .medium }
        return .regular
    }
}

private struct SmallWidgetView: View {
    let date: Date
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .font(.title3)
                    .foregroundStyle(WidgetTheme.accent)

                Spacer()

                Text(WidgetTimeFormatter.time(
                    date,
                    timezoneIdentifier: snapshot?.timeZoneIdentifier ?? TimeZone.current.identifier
                ))
                .font(.caption.weight(.semibold))
                .foregroundStyle(WidgetTheme.accent)
                .monospacedDigit()
            }

            Spacer(minLength: 4)

            if let snapshot, let featured = snapshot.currentPrayer ?? snapshot.nextPrayer {
                let isCurrent = snapshot.currentPrayer != nil
                let countdownDate = isCurrent ? featured.end : featured.time

                VStack(alignment: .center, spacing: 2) {
                    Text(featured.name)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WidgetTheme.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(WidgetLocalization.dynamic(isCurrent ? "ends in" : "in"))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(WidgetTheme.accent)

                    Text(countdownDate, style: .timer)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(WidgetTheme.accent)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                Spacer(minLength: 0)

                HStack(spacing: 24) {
                    Image(systemName: "clock")
                        .font(.title3)
                    Image(systemName: "building.columns")
                        .font(.title3)
                    Image(systemName: "star")
                        .font(.title3)
                }
                .foregroundStyle(WidgetTheme.primary.opacity(0.35))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 5)
            } else {
                Text("Open Salah to load prayer times")
                    .font(.caption)
                    .foregroundStyle(WidgetTheme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }
}

private struct MediumWidgetView: View {
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
                            Text(snapshot.gregorianSummary)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                            Text(snapshot.hijriSummary)
                                .font(.caption2)
                                .foregroundStyle(WidgetTheme.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 5)

                    Text(featuredHeading(featured, isCurrent: isCurrent))
                        .font(.caption2.weight(.semibold))
                        .tracking(1.1)
                        .foregroundStyle(WidgetTheme.accent)
                    Text(featured.name)
                        .font(.system(size: 31, weight: .medium, design: .serif))
                        .foregroundStyle(WidgetTheme.primary)
                        .lineLimit(1)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(WidgetLocalization.dynamic(isCurrent ? "ends in" : "in"))
                        Text(countdownDate, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(WidgetTheme.accent)

                    Spacer(minLength: 4)

                    HStack(spacing: 8) {
                        Image(systemName: "moon.stars.fill")
                            .font(.title3)
                        Image(systemName: "building.columns.fill")
                            .font(.title3)
                            .opacity(0.35)
                    }
                    .foregroundStyle(WidgetTheme.accent.opacity(0.7))
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

private struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let snapshot, let featured = snapshot.currentPrayer ?? snapshot.nextPrayer {
                let isCurrent = snapshot.currentPrayer != nil
                let countdownDate = isCurrent ? featured.end : featured.time

                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.caption)
                        .foregroundStyle(WidgetTheme.accent)
                        .padding(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(WidgetTheme.accent.opacity(0.7), lineWidth: 1)
                        )
                    Text(snapshot.hijriSummary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(WidgetTheme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 14)

                Text(featuredHeading(featured, isCurrent: isCurrent))
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(WidgetTheme.accent)
                Text(featured.name)
                    .font(.system(size: 36, weight: .medium, design: .serif))
                    .foregroundStyle(WidgetTheme.primary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(WidgetLocalization.dynamic(isCurrent ? "ends in" : "in"))
                    Text(countdownDate, style: .timer)
                        .monospacedDigit()
                }
                .font(.headline.weight(.semibold))
                .foregroundStyle(WidgetTheme.accent)

                Spacer(minLength: 14)

                Rectangle()
                    .fill(WidgetTheme.divider)
                    .frame(height: 1)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(snapshot.prayers) { prayer in
                        HStack(spacing: 9) {
                            Image(systemName: prayer.symbolName)
                                .font(.caption)
                                .frame(width: 17)
                                .foregroundStyle(prayer.largeIconColor)
                            Text(prayer.name)
                                .fontWeight(prayer.rowWeight)
                                .foregroundStyle(prayer.largeRowColor)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(WidgetTimeFormatter.time(prayer.time, timezoneIdentifier: snapshot.timeZoneIdentifier))
                                .font(.subheadline.monospacedDigit())
                                .fontWeight(prayer.rowWeight)
                                .foregroundStyle(prayer.largeRowColor)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                    }
                }
            } else {
                Text("Open Salah to load prayer times")
                    .font(.subheadline)
                    .foregroundStyle(WidgetTheme.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(20)
    }
}

private func featuredHeading(_ prayer: WidgetPrayer, isCurrent: Bool) -> String {
    if prayer.isNafl {
        return isCurrent ? WidgetLocalization.string("CURRENT NAFL PRAYER") : WidgetLocalization.string("NEXT NAFL PRAYER")
    }
    return isCurrent ? WidgetLocalization.string("CURRENT PRAYER") : WidgetLocalization.string("NEXT PRAYER")
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
            .systemLarge,
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

#Preview(as: .systemLarge) {
    SalahWidgets()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: sampleSnapshot().snapshot(at: .now))
}

#Preview(as: .accessoryInline) {
    SalahWidgets()
} timeline: {
    SimpleEntry(date: .now, configuration: ConfigurationAppIntent(), snapshot: sampleSnapshot().snapshot(at: .now))
}
