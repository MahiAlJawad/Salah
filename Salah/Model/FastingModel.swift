//
//  FastingModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 10/3/24.
//

import SwiftUI

struct FastingModel {
    enum EventType {
        case sahri
        case iftar
        
        var title: String {
            switch self {
            case .sahri: return "Sahri"
            case .iftar: return "Iftar"
            }
        }
        
        var backgroundCanvas: LinearGradient {
            switch self {
            case .sahri:
                return .init(colors: [.green, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .iftar:
                return .init(colors: [.green, .red], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        
        var alertKey: String {
            switch self {
            case .sahri: return "sahriAlert"
            case .iftar: return "iftarAlert"
            }
        }
    }
    
    enum FastingEvent {
        case sahriToGo(_ startTime: String, _ endTime: String)
        case iftarToGo(_ startTime: String, _ endTime: String)
        
        var timerIndicatorDescription: String {
            switch self {
            case .sahriToGo: return "Time ends in"
            case .iftarToGo: return "Time starts in"
            }
        }
        
        var type: EventType {
            switch self {
            case .sahriToGo: return .sahri
            case .iftarToGo: return .iftar
            }
        }
        
        var sahriLastTime: String {
            switch self {
            case .iftarToGo(let sahriLastTime, _):
                return "Sahri    \(sahriLastTime.time12String)"
            case .sahriToGo(_, let sahriLastTime):
                return "Sahri    \(sahriLastTime.time12String)"
            }
        }
        
        var iftarStartTime: String {
            switch self {
            case .iftarToGo(_, let iftarStartTime):
                return "Iftar    \(iftarStartTime.time12String)"
            case .sahriToGo(let iftarStartTime, _):
                return "Iftar    \(iftarStartTime.time12String)"
            }
        }
        
        var totalTimeDurationInSeconds: Double {
            switch self {
            case let .sahriToGo(startTime, endTime), let .iftarToGo(startTime, endTime):
                let startTime = startTime.toDate
                let endTime = endTime.toDate
                
                if startTime > endTime { // Late Isha case
                    let nextDayTime = endTime.addingTimeInterval(TimeInterval(3600 * 24))
                    return startTime.distance(to: nextDayTime)
                } else {
                    return startTime.distance(to: endTime)
                }
            }
        }
        
        func elapsedTime(from currentTime: String) -> Double {
            switch self {
            case let .sahriToGo(startTime, _), let .iftarToGo(startTime, _):
                let currentTime = currentTime.toDateWithSeconds
                let startTime = startTime.toDate
                
                if currentTime < startTime { // Late 12:00AM case
                    let nextDayTime = currentTime.addingTimeInterval(TimeInterval(3600 * 24))
                    return startTime.distance(to: nextDayTime)
                } else {
                    return startTime.distance(to: currentTime)
                }
            }
        }
    }
    
    struct DateSummary {
        let gregorian: String
        let hijri: String
        
        init(_ dateResponse: DateResponse) {
            let weekDay = dateResponse.gregorian.weekday.en
            let day = dateResponse.gregorian.day
            let month = dateResponse.gregorian.month.en
            
            gregorian = "\(weekDay), \(day) \(month)"
            
            let dayHijri = dateResponse.hijri.day
            let monthHijri = dateResponse.hijri.month.en
            
            hijri = "\(dayHijri) \(monthHijri)"
        }
    }
}

extension FastingModel {
    static func getCurrentFastingEvent(from timings: TimingResponse, currentTime: String, cautionDelay: CautionDelay) -> FastingEvent {
        let currentTime = currentTime.toDateWithSeconds
        let imsak = timings.imsak.toDate
        let iftar = timings.sunset.addMinits(cautionDelay.delay).toDate
        
        if currentTime >= imsak, currentTime < iftar {
            return .iftarToGo(timings.imsak, timings.sunset.addMinits(cautionDelay.delay))
        } else {
            return .sahriToGo(timings.sunset.addMinits(cautionDelay.delay), timings.imsak)
        }
    }
}
