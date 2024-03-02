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
        case startTimer(_ totalRemainingTime: Double)
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
        case waqtOngoing(_ waqt: Salah.Waqt, _ endTime: String)
        case waqtToStart(_ waqt: Salah.Waqt,_ startingTime: String)
        
        func remainingTimeInSeconds(from currentTime: String) -> Double {
            switch self {
            case .waqtOngoing(_, let timeToTrack), .waqtToStart(_, let timeToTrack):
                let currentTime = currentTime.toDate
                let timeToTrack = timeToTrack.toDate
                
                if currentTime > timeToTrack { // Late Isha case
                    let nextDayTime = timeToTrack.addingTimeInterval(TimeInterval(3600 * 24))
                    return currentTime.distance(to: nextDayTime)
                } else {
                    return currentTime.distance(to: timeToTrack)
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
        let currentTime = currentTime.toDate
        let imsak = timings.imsak.toDate
        let fajr = timings.fajr.toDate
        let sunrise = timings.sunrise.toDate
        let dhuhr = timings.dhuhr.toDate
        let asr = timings.asr.toDate
        let sunset = timings.sunset.toDate
        let maghrib = timings.maghrib.toDate
        let isha = timings.isha.toDate
        
        if currentTime < imsak {
            return .waqtOngoing(.isha, timings.imsak.subtractMinits(1))
        } else if currentTime >= imsak, currentTime < fajr {
            return .waqtToStart(.fajr, timings.fajr)
        } else if currentTime >= fajr, currentTime < sunrise {
            return .waqtOngoing(.fajr, timings.sunrise.subtractMinits(1))
        } else if currentTime >= sunrise, currentTime < dhuhr {
            return .waqtToStart(.dhuhr, timings.dhuhr)
        } else if currentTime >= dhuhr, currentTime < asr {
            return .waqtOngoing(.dhuhr, timings.asr.subtractMinits(1))
        } else if currentTime >= asr, currentTime < sunset {
            return .waqtOngoing(.asr, timings.sunset.subtractMinits(1))
        } else if currentTime >= sunset, currentTime < maghrib {
            return .waqtToStart(.maghrib, timings.maghrib)
        } else if currentTime >= maghrib, currentTime < isha {
            return .waqtOngoing(.maghrib, timings.isha.subtractMinits(1))
        } else {
            return .waqtOngoing(.isha, timings.imsak.subtractMinits(1))
        }
    }
}
