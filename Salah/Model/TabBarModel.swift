//
//  TabBarModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 23/2/24.
//

import Foundation

struct TabBarModel {
    enum Item {
        case timings
        case tracker
        case more
        
        var title: String {
            switch self {
            case .timings: return "Timings"
            case .tracker: return "Tracker"
            case .more: return "More"
            }
        }
        
        var icon: String {
            switch self {
            case .timings: return "calendar.badge.clock"
            case .tracker: return "checklist"
            case .more: return "list.bullet"
            }
        }
    }
}
