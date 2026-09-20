import Foundation
import WidgetKit

enum WidgetDataPublisher {
    static func save(
        prayerDay: PrayerDay,
        completed: Set<PrayerType>,
        naflCompletedMask: Int = 0,
        nextDay: PrayerDay? = nil,
        futureDays: [PrayerDay] = []
    ) {
        let today = LocalDay(.now, timeZone: prayerDay.timeZone)
        guard prayerDay.localDay == today else { return }

        let now = Date()

        let scheduleItems = makeScheduleItems(
            day: prayerDay,
            completed: completed,
            naflCompletedMask: naflCompletedMask
        )
        let upcomingSchedules = ([nextDay].compactMap { $0 } + futureDays)
            .filter { $0.localDay > prayerDay.localDay }
            .reduce(into: [String: WidgetDaySchedule]()) { schedules, day in
                schedules[day.localDay.key] = WidgetDaySchedule(
                    localDayKey: day.localDay.key,
                    gregorianSummary: day.gregorianSummary,
                    hijriSummary: day.hijriSummary,
                    sahri: day.sahri,
                    iftar: day.iftar,
                    prayers: makeScheduleItems(day: day, completed: [], naflCompletedMask: 0)
                )
            }
            .values
            .sorted { $0.localDayKey < $1.localDayKey }
        let nextDaySchedule = upcomingSchedules.first
        let additionalFutureSchedules = Array(upcomingSchedules.dropFirst())
        let tomorrowItem = nextDaySchedule?.prayers.first { $0.kind == .fajr }

        let moment = WidgetSnapshot.moment(
            at: now,
            prayers: scheduleItems,
            tomorrowFajr: tomorrowItem,
            timeZoneIdentifier: prayerDay.timeZoneIdentifier
        )
        let flaggedItems = scheduleItems.map { item in
            WidgetPrayer(
                name: item.name,
                time: item.time,
                end: item.end,
                symbolName: item.symbolName,
                completed: item.completed,
                isNext: moment.next?.name == item.name && moment.next?.time == item.time,
                isCurrent: moment.current?.name == item.name && moment.current?.time == item.time,
                kind: item.kind
            )
        }

        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            localDayKey: prayerDay.localDay.key,
            gregorianSummary: prayerDay.gregorianSummary,
            hijriSummary: prayerDay.hijriSummary,
            timeZoneIdentifier: prayerDay.timeZoneIdentifier,
            sahri: prayerDay.sahri,
            iftar: prayerDay.iftar,
            prayers: flaggedItems,
            currentPrayer: moment.current,
            nextPrayer: moment.next,
            tomorrowFajr: tomorrowItem,
            nextDay: nextDaySchedule,
            futureDays: additionalFutureSchedules
        )

        WidgetDataStore.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: "SalahWidgets")
    }

    static func updateCompletion(
        prayer: PrayerType,
        day: LocalDay,
        completed: Bool
    ) {
        guard let kind = WidgetPrayerKind(rawValue: prayer.rawValue) else { return }
        WidgetDataStore.updateCompletion(kind: kind, localDayKey: day.key, completed: completed)
    }

    private static func makeScheduleItems(
        day: PrayerDay,
        completed: Set<PrayerType>,
        naflCompletedMask: Int
    ) -> [WidgetPrayer] {
        let prayerItems = day.windows.map { window in
            WidgetPrayer(
                name: window.prayer.title,
                time: window.start,
                end: window.end,
                symbolName: window.prayer.symbol,
                completed: completed.contains(window.prayer),
                isNext: false,
                isCurrent: false,
                kind: WidgetPrayerKind(rawValue: window.prayer.rawValue)
            )
        }
        let sunriseItem = WidgetPrayer(
            name: L10n.string("Sunrise"),
            time: day.sunrise,
            end: day.sunrise,
            symbolName: "sunrise.fill",
            completed: false,
            isNext: false,
            isCurrent: false,
            kind: .sunrise
        )
        let naflItems = [
            WidgetPrayer(
                name: L10n.string("Tahajjud"),
                time: day.localDay.date(in: day.timeZone, hour: 0) ?? day.windows[0].start,
                end: day.windows.first(where: { $0.prayer == .fajr })?.start ?? day.windows[0].start,
                symbolName: NaflPractice.tahajjud.symbol,
                completed: naflCompletedMask & (1 << NaflPractice.tahajjud.rawValue) != 0,
                isNext: false,
                isCurrent: false,
                kind: .tahajjud
            ),
            WidgetPrayer(
                name: L10n.string("Ishrak"),
                time: day.sunrise.addingTimeInterval(PrayerTimeline.ishrakSunriseBuffer),
                end: (day.windows.first(where: { $0.prayer == .dhuhr })?.start ?? day.sunrise)
                    .addingTimeInterval(-PrayerTimeline.ishrakDhuhrBuffer),
                symbolName: NaflPractice.ishrak.symbol,
                completed: naflCompletedMask & (1 << NaflPractice.ishrak.rawValue) != 0,
                isNext: false,
                isCurrent: false,
                kind: .ishrak
            )
        ]
        return prayerItems.reduce(into: naflItems) { result, item in
            result.append(item)
            if item.kind == .fajr { result.append(sunriseItem) }
        }
    }
}
