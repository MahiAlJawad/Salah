//
//  TimerViewModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 10/3/24.
//

import Foundation

struct TimerModel {
    enum TimerEvent {
        case startTimer(totalRemainingTime: Double, elapsedTime: Double, isWaqtOngoing: Bool)
        case refresh
        case completed
    }
}
