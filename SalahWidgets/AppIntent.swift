//
//  AppIntent.swift
//  SalahWidgets
//
//  Created by Kazi Tanjim Shakib on 27/7/26.
//

import WidgetKit
import AppIntents

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "Configure the Salah prayer-times widget." }
}

struct SetPrayerCompletionIntent: AppIntent {
    static var title: LocalizedStringResource { "Update Prayer Completion" }
    static var description: IntentDescription { "Marks the current prayer as completed or not completed." }
    static var openAppWhenRun: Bool { false }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Prayer")
    var prayerKind: String

    @Parameter(title: "Day")
    var localDayKey: String

    @Parameter(title: "Time Zone")
    var timeZoneIdentifier: String

    @Parameter(title: "Completed")
    var completed: Bool

    init() { }

    init(
        prayerKind: WidgetPrayerKind,
        localDayKey: String,
        timeZoneIdentifier: String,
        completed: Bool
    ) {
        self.prayerKind = prayerKind.rawValue
        self.localDayKey = localDayKey
        self.timeZoneIdentifier = timeZoneIdentifier
        self.completed = completed
    }

    func perform() async throws -> some IntentResult {
        guard let kind = WidgetPrayerKind(rawValue: prayerKind), kind.isObligatory else {
            return .result()
        }

        WidgetPrayerCompletionStore.record(
            prayerKind: kind,
            localDayKey: localDayKey,
            timeZoneIdentifier: timeZoneIdentifier,
            completed: completed
        )
        WidgetDataStore.updateCompletion(
            kind: kind,
            localDayKey: localDayKey,
            completed: completed
        )
        return .result()
    }
}
