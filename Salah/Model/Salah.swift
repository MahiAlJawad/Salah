//
//  Salah.swift
//  Salah
//
//  Created by Mahi Al Jawad on 18/2/24.
//

import Foundation
import SwiftUI

extension Salah {
    enum Waqt: String, CaseIterable, Identifiable {
        var id: String { rawValue }
        
        case fajr, dhuhr, asr, maghrib, isha
        
        var title: String {
            switch self {
            case .fajr: return "Fajr"
            case .dhuhr: return "Dhuhr"
            case .asr: return "Asr"
            case .maghrib: return "Maghrib"
            case .isha: return "Isha"
            }
        }
        
        var icon: String {
            switch self {
            case .fajr: return "moon.dust.fill"
            case .dhuhr: return "sun.max.fill"
            case .asr: return "sun.min.fill"
            case .maghrib: return "sun.dust.fill"
            case .isha: return "moon.zzz.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .fajr: return .indigo
            case .dhuhr: return .yellow
            case .asr: return .orange
            case .maghrib: return .red
            case .isha: return .blue
            }
        }
        
        var backgroundCanvas: LinearGradient {
            switch self {
            case .fajr: 
                return .init(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .dhuhr:
                return .init(colors: [.orange, .yellow, .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .asr:
                return .init(colors: [.red, .red.opacity(0.5), .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .maghrib:
                return .init(colors: [.red, .purple, .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .isha:
                return .init(colors: [.purple, .indigo, .brown], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

struct Salah {
    let waqt: Waqt
    let startingTime: String
    let endingTime: String
    
    init(waqt: Waqt, timingData: TimingResponse, cautionDelay: CautionDelay) {
        self.waqt = waqt
        
        switch waqt {
        case .fajr:
            startingTime = timingData.fajr.time12String
            endingTime = timingData.sunrise.subtractMinits(1).time12String
        case .dhuhr:
            startingTime = timingData.dhuhr.time12String
            endingTime = timingData.asr.subtractMinits(1).time12String
        case .asr:
            startingTime = timingData.asr.time12String
            endingTime = timingData.sunset.subtractMinits(1).time12String
        case .maghrib:
            startingTime = timingData.maghrib.addMinits(cautionDelay.delay).time12String
            endingTime = timingData.isha.subtractMinits(1).time12String
        case .isha:
            startingTime = timingData.isha.time12String
            endingTime = timingData.imsak.subtractMinits(1).time12String
        }
    }
}
