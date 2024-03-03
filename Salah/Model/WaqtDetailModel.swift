//
//  WaqtDetailModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 27/2/24.
//

import Foundation
import SwiftUI

struct WaqtDetailModel {
    enum TimerEvent {
        case startTimer(totalRemainingTime: Double, elapsedTime: Double)
        case completed
    }
    
    enum SunSchedules {
        case sunrise(String)
        case sunset(String)
        
        var time: String {
            switch self {
            case .sunrise(let time): time.time12String
            case .sunset(let time): time.time12String
            }
        }
        
        var icon: String {
            switch self {
            case .sunrise: "sun.horizon.fill"
            case .sunset: "sun.dust.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .sunrise: return .orange
            case .sunset: return .red
            }
        }
        
        var title: String {
            switch self {
            case .sunrise: return "Sunrise: \(time)"
            case .sunset: return "Sunset: \(time)"
            }
        }
    }
    
    enum WaqtType {
        case waqtOngoing(_ waqt: Salah.Waqt, _ startTime: String, _ endTime: String)
        case waqtToStart(_ waqt: Salah.Waqt, _ startTime: String, _ endTime: String)
        
        var timerIndicatorDescription: String {
            switch self {
            case .waqtOngoing: return "Ends in"
            case .waqtToStart: return "Starts in"
            }
        }
        
        var totalTimeDurationInSeconds: Double {
            switch self {
            case .waqtOngoing(_, let startTime, let endTime), .waqtToStart(_, let startTime, let endTime):
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
            case .waqtOngoing(_, let startTime, _), .waqtToStart(_, let startTime, _):
                let currentTime = currentTime.toDateWithSeconds
                let startTime = startTime.toDate
                
                if currentTime < startTime {
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

extension WaqtDetailModel {
    static func getCurrentWaqtType(from timings: TimingResponse, currentTime: String) -> WaqtType {
        let currentTime = currentTime.toDateWithSeconds
        let imsak = timings.imsak.toDate
        let fajr = timings.fajr.toDate
        let sunrise = timings.sunrise.toDate
        let dhuhr = timings.dhuhr.toDate
        let asr = timings.asr.toDate
        let sunset = timings.sunset.toDate
        let maghrib = timings.maghrib.toDate
        let isha = timings.isha.toDate
        
        if currentTime < imsak {
            return .waqtOngoing(.isha, timings.isha, timings.imsak)
        } else if currentTime >= imsak, currentTime < fajr {
            return .waqtToStart(.fajr, timings.imsak, timings.fajr)
        } else if currentTime >= fajr, currentTime < sunrise {
            return .waqtOngoing(.fajr, timings.fajr, timings.sunrise)
        } else if currentTime >= sunrise, currentTime < dhuhr {
            return .waqtToStart(.dhuhr, timings.sunrise, timings.dhuhr)
        } else if currentTime >= dhuhr, currentTime < asr {
            return .waqtOngoing(.dhuhr, timings.dhuhr, timings.asr)
        } else if currentTime >= asr, currentTime < sunset {
            return .waqtOngoing(.asr, timings.asr, timings.sunset)
        } else if currentTime >= sunset, currentTime < maghrib {
            return .waqtToStart(.maghrib, timings.sunset, timings.maghrib)
        } else if currentTime >= maghrib, currentTime < isha {
            return .waqtOngoing(.maghrib, timings.maghrib, timings.isha)
        } else {
            return .waqtOngoing(.isha, timings.isha, timings.imsak)
        }
    }
}
