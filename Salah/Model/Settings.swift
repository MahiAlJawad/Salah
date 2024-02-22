//
//  Settings.swift
//  Salah
//
//  Created by Mahi Al Jawad on 22/2/24.
//

import Foundation

enum Location {
    case city(BDDistrict)
    case coordinate(lat: Double, lon: Double)
    
    var lattitude: Double {
        switch self {
        case .city(let district): return Double(district.lat) ?? 0
        case .coordinate(let lattitude, _): return lattitude
        }
    }
    
    var longitude: Double {
        switch self {
        case .city(let district): return Double(district.lon) ?? 0
        case .coordinate(_, let longitude): return longitude
        }
    }
}

enum Method {
    case UIS_Karachi
    case byLocation
}

enum CautionDelay {
    case IslamicFoundation
    case manual(seconds: Int)
    
    var delay: Int {
        switch self {
        case .IslamicFoundation: return 3
        case .manual(let seconds): return seconds
        }
    }
}

enum Madhab {
    case hanafi
    case others
}

enum HijriDateAdjustment {
    case adjustDays(Int)
    
    var days: Int {
        switch self {
        case .adjustDays(let days): return days
        }
    }
}
