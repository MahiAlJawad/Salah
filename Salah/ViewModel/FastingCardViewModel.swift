//
//  FastingCardViewModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 10/3/24.
//

import SwiftUI
import Combine

@Observable
final class FastingCardViewModel {
    typealias Model = FastingModel
    
    @ObservationIgnored
    @AppStorage(Model.EventType.sahri.alertKey) private var sahriAlert: Bool = false {
        didSet {
            isSahriAlertEnabled = sahriAlert
        }
    }
    
    @ObservationIgnored
    @AppStorage(Model.EventType.iftar.alertKey) private var iftarAlert: Bool = false {
        didSet {
            isIftarAlertEnabled = iftarAlert
        }
    }
    
    private var cancellable: Cancellable?
    private var dataResponse: DataResponse
    private var currentTimeString: String
    
    var isSahriAlertEnabled: Bool
    var isIftarAlertEnabled: Bool
    
    var fastingEvent: Model.FastingEvent
    var timerEventSubject = PassthroughSubject<TimerModel.TimerEvent, Never>()
    
    
    init(dataResponse: DataResponse) {
        self.dataResponse = dataResponse
        let time = Date().time24String
        currentTimeString = time
        fastingEvent = Model.getCurrentFastingEvent(
            from: dataResponse.timings,
            currentTime: time,
            cautionDelay: .IslamicFoundation
        )
        
        isSahriAlertEnabled = UserDefaults.standard.value(forKey: Model.EventType.sahri.alertKey) as? Bool ?? false
        isIftarAlertEnabled = UserDefaults.standard.value(forKey: Model.EventType.iftar.alertKey) as? Bool ?? false
        observeTimerEvents()
    }
    
    private func observeTimerEvents() {
        updateFastingEventTimer()
        cancellable = timerEventSubject.sink { [weak self] event in
            switch event {
            case .completed, .refresh:
                self?.updateFastingEventTimer()
            default:
                break
            }
        }
    }
    
    private func updateFastingEventTimer() {
        currentTimeString = Date().time24String
        fastingEvent = Model.getCurrentFastingEvent(
            from: dataResponse.timings,
            currentTime: currentTimeString,
            cautionDelay: .IslamicFoundation
        )
        
        timerEventSubject.send(
            .startTimer(
                totalRemainingTime: fastingEvent.totalTimeDurationInSeconds,
                elapsedTime: fastingEvent.elapsedTime(from: currentTimeString),
                isWaqtOngoing: false
            )
        )
    }
    
    var dateSummary: Model.DateSummary {
        .init(dataResponse.date)
    }
    
    var totalDuration: Double {
        fastingEvent.totalTimeDurationInSeconds
    }
    
    var elapsedTime: Double {
        fastingEvent.elapsedTime(from: currentTimeString)
    }
    
    var showTimer: Bool {
        Date().dateString == dataResponse.date.gregorian.date
    }
    
    func toggleSahriAlert() {
        sahriAlert.toggle()
    }
    
    func toggleIftarAlert() {
        iftarAlert.toggle()
    }
}


