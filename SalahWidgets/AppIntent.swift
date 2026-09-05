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
