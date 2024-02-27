//
//  WaqtDetailModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 27/2/24.
//

import Foundation
import SwiftUI

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
