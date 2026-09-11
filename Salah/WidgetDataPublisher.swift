import Foundation
import WidgetKit

enum WidgetDataPublisher {
    static func save(
        prayerDay: PrayerDay,
        completed: Set<PrayerType>,
        nextDay: PrayerDay? = nil,
        futureDays: [PrayerDay] = []
    ) {
        let today = LocalDay(.now, timeZone: prayerDay.timeZone)
        guard prayerDay.localDay == today else { return }

        let now = Date()

        let scheduleItems = makeScheduleItems(day: prayerDay, completed: completed)
        let upcomingSchedules = ([nextDay].compactMap { $0 } + futureDays)
            .filter { $0.localDay > prayerDay.localDay }
            .reduce(into: [String: WidgetDaySchedule]()) { schedules, day in
                schedules[day.localDay.key] = WidgetDaySchedule(
                    localDayKey: day.localDay.key,
                    gregorianSummary: day.gregorianSummary,
                    hijriSummary: day.hijriSummary,
                    prayers: makeScheduleItems(day: day, completed: [])
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
        guard let snapshot = WidgetDataStore.load(), snapshot.localDayKey == day.key else { return }

        let updatedPrayers = snapshot.prayers.map { item in
            item.name == prayer.title
                ? WidgetPrayer(
                    name: item.name,
                    time: item.time,
                    end: item.end,
                    symbolName: item.symbolName,
                    completed: completed,
                    isNext: item.isNext,
                    isCurrent: item.isCurrent,
                    kind: item.kind
                )
                : item
        }

        let updated = WidgetSnapshot(
            updatedAt: .now,
            localDayKey: snapshot.localDayKey,
            gregorianSummary: snapshot.gregorianSummary,
            hijriSummary: snapshot.hijriSummary,
            timeZoneIdentifier: snapshot.timeZoneIdentifier,
            prayers: updatedPrayers,
            currentPrayer: updating(snapshot.currentPrayer, prayer: prayer, completed: completed),
            nextPrayer: updating(snapshot.nextPrayer, prayer: prayer, completed: completed),
            tomorrowFajr: snapshot.tomorrowFajr,
            nextDay: snapshot.nextDay,
            futureDays: snapshot.futureDays
        )

        WidgetDataStore.save(updated)
        WidgetCenter.shared.reloadTimelines(ofKind: "SalahWidgets")
    }

    /// Returns `item` with `completed` updated, but only when its name matches
    /// `prayer`; otherwise `item` is left untouched.
    private static func updating(
        _ item: WidgetPrayer?,
        prayer: PrayerType,
        completed: Bool
    ) -> WidgetPrayer? {
        item.map { current in
            current.name == prayer.title
                ? WidgetPrayer(
                    name: current.name,
                    time: current.time,
                    end: current.end,
                    symbolName: current.symbolName,
                    completed: completed,
                    isNext: current.isNext,
                    isCurrent: current.isCurrent,
                    kind: current.kind
                )
                : current
        }
    }

    private static func makeScheduleItems(day: PrayerDay, completed: Set<PrayerType>) -> [WidgetPrayer] {
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
        return prayerItems.reduce(into: [WidgetPrayer]()) { result, item in
            result.append(item)
            if item.kind == .fajr { result.append(sunriseItem) }
        }
    }
}
