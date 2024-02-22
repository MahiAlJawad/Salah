//
//  Salah.swift
//  Salah
//
//  Created by Mahi Al Jawad on 18/2/24.
//

import Foundation

extension Salah {
    enum Waqt {
        case fajr, dhur, asr, maghrib, isha
    }
}

struct Salah {
    let waqt: Waqt
    let startingTime: String
    let endingTime: String
    
    init(waqt: Waqt, timingData: TimingResponse) {
        self.waqt = waqt
        
        switch waqt {
        case .fajr:
            startingTime = timingData.fajr
            endingTime = timingData.sunrise.subtractMinits(1)
        case .dhur:
            startingTime = timingData.dhuhr
            endingTime = timingData.asr.subtractMinits(1)
        case .asr:
            startingTime = timingData.asr
            endingTime = timingData.sunset.subtractMinits(1)
        case .maghrib:
            startingTime = timingData.maghrib
            endingTime = timingData.isha.subtractMinits(1)
        case .isha:
            startingTime = timingData.isha
            endingTime = timingData.imsak.subtractMinits(1)
        }
    }
}
