import SwiftUI
import WidgetKit

struct FastingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FastingTimelineEntry {
        FastingTimelineEntry(date: .now, snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FastingTimelineEntry) -> Void) {
        let now = Date()
        completion(FastingTimelineEntry(
            date: now,
            snapshot: WidgetDataStore.load()?.snapshot(at: now)
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FastingTimelineEntry>) -> Void) {
        let now = Date()
        let stored = WidgetDataStore.load()
        let transitionDates = stored?.fastingTransitionDates(after: now) ?? []
        let entries = ([now] + transitionDates).map { date in
            FastingTimelineEntry(date: date, snapshot: stored?.snapshot(at: date))
        }
        let policy: TimelineReloadPolicy = transitionDates.isEmpty
            ? .after(now.addingTimeInterval(6 * 60 * 60))
            : .atEnd
        completion(Timeline(entries: entries, policy: policy))
    }
}

struct FastingTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct FastingTimesWidget: Widget {
    let kind = WidgetDataStore.fastingWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FastingTimelineProvider()) { entry in
            FastingTimesWidgetView(entry: entry)
        }
        .configurationDisplayName("Sahri & Iftar")
        .description("Shows the next Sahri or Iftar time.")
        .supportedFamilies([.accessoryRectangular])
        .contentMarginsDisabled()
    }
}

private struct FastingTimesWidgetView: View {
    let entry: FastingTimelineEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot,
               let event = snapshot.nextFastingEvent(after: entry.date) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: event.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 28)
                        .widgetAccentable()

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.name)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(WidgetTimeFormatter.time(
                            event.time,
                            timezoneIdentifier: snapshot.timeZoneIdentifier
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(WidgetLocalization.dynamic("Open Salah to refresh times"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .environment(\.locale, WidgetLocalization.locale)
        .containerBackground(for: .widget) {
            WidgetTheme.background
        }
    }
}

#Preview(as: .accessoryRectangular) {
    FastingTimesWidget()
} timeline: {
    FastingTimelineEntry(date: .now, snapshot: fastingPreviewSnapshot)
}

private let fastingPreviewSnapshot = WidgetSnapshot(
    updatedAt: .now,
    localDayKey: "2026-09-15",
    gregorianSummary: "Tuesday, 15 September",
    hijriSummary: "3 Rabi al-Awwal 1448",
    timeZoneIdentifier: TimeZone.current.identifier,
    sahri: .now.addingTimeInterval(-60 * 60),
    iftar: .now.addingTimeInterval(6 * 60 * 60),
    prayers: [],
    currentPrayer: nil,
    nextPrayer: nil,
    tomorrowFajr: nil,
    nextDay: nil
)
