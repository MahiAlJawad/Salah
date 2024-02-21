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
    
//    init(waqt: Waqt, timingData: TimingResponse) {
//        self.waqt = waqt
//        
//        switch waqt {
//        case .fajr:
//            startingTime = timingData.fajr
//            endingTime = Int(timingData.sunrise) - 1
//        case .dhur:
//            <#code#>
//        case .asr:
//            <#code#>
//        case .maghrib:
//            <#code#>
//        case .isha:
//            <#code#>
//        }
//    }
}
