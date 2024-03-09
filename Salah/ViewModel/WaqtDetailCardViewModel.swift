//
//  WaqtDetailCardViewModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 3/3/24.
//

import SwiftUI
import Combine

@Observable
class WaqtDetailCardViewModel {
    typealias Model = WaqtDetailModel
    private let dataResponse: DataResponse
    var currentWaqtType: Model.WaqtType {
        didSet {
            switch currentWaqtType {
            case let .waqtOngoing(waqt, _, _):
                timingsViewWaqtUpdater?.send(waqt)
            case .waqtToStart(_, _, _):
                timingsViewWaqtUpdater?.send(nil)
            }
        }
    }
    
    var timerEventSubject = PassthroughSubject<Model.TimerEvent, Never>()
    private var currentTimeString: String
    private var cancellable: Cancellable?
    private weak var timingsViewWaqtUpdater: PassthroughSubject<Salah.Waqt?, Never>?
    
    init(dataResponse: DataResponse, waqtUpdater: PassthroughSubject<Salah.Waqt?, Never>) {
        self.dataResponse = dataResponse
        let time = Date().time24String
        currentTimeString = time
        currentWaqtType = Model.getCurrentWaqtType(from: dataResponse.timings, currentTime: time, cautionDelay: .IslamicFoundation)
        timingsViewWaqtUpdater = waqtUpdater
        observeTimerEvents()
    }
    
    var totalWaqtDuration: Double {
        currentWaqtType.totalTimeDurationInSeconds
    }
    
    var elapsedTime: Double {
        currentWaqtType.elapsedTime(from: currentTimeString)
    }
    
    var isWaqtOngoing: Bool {
        switch currentWaqtType {
        case .waqtOngoing: return true
        case .waqtToStart: return false
        }
    }
    
    private func observeTimerEvents() {
        updateCurrentWaqtTimer()
        cancellable = timerEventSubject.sink { [weak self] event in
            switch event {
            case .completed, .refresh:
                self?.updateCurrentWaqtTimer()
            default:
                break
            }
        }
    }
    
    private func updateCurrentWaqtTimer() {
        currentTimeString = Date().time24String
        currentWaqtType = Model.getCurrentWaqtType(from: dataResponse.timings, currentTime: currentTimeString, cautionDelay: .IslamicFoundation)
        
        timerEventSubject.send(
            .startTimer(
                totalRemainingTime: currentWaqtType.totalTimeDurationInSeconds,
                elapsedTime: currentWaqtType.elapsedTime(from: currentTimeString), isWaqtOngoing: isWaqtOngoing
            )
        )
    }
    
    var currentWaqt: Salah.Waqt {
        switch currentWaqtType {
        case let .waqtOngoing(waqt, _, _), let .waqtToStart(waqt, _, _):
            return waqt
        }
    }
    
    var timingResponse: TimingResponse {
        dataResponse.timings
    }
    
    var sunriseSchedule: Model.SunSchedules {
        .sunrise(timingResponse.sunrise)
    }
    
    var sunsetSchedule: Model.SunSchedules {
        .sunset(timingResponse.sunset)
    }
    
    var dateSummary: Model.DateSummary {
        .init(dataResponse.date)
    }
    
    var showTimer: Bool {
        Date().dateString == dataResponse.date.gregorian.date
    }
}
