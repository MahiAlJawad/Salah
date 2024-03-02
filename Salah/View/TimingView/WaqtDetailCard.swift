//
//  WaqtDetailCard.swift
//  Salah
//
//  Created by Mahi Al Jawad on 25/2/24.
//

import SwiftUI
import Combine

struct GaugeProgressStyle: ProgressViewStyle {
    var remainingStrokeColor = Color.secondary.opacity(0.5)
    var strokeColor = Color.blue
    var strokeWidth = 10.0

    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0
        
        return ZStack {
            Circle()
                .stroke(remainingStrokeColor, style: StrokeStyle(lineWidth: strokeWidth))
            Circle()
                .trim(from: 0, to: fractionCompleted)
                .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .square))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct TimerView: View {
    @State private var totalDuration: Double = 0
    @State private var progress: Double = 0
    @State var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    @Binding private var timerEventSubject: PassthroughSubject<WaqtDetailModel.TimerEvent, Never>
    
    init(timerEventSubject: Binding<PassthroughSubject<WaqtDetailModel.TimerEvent, Never>>) {
        self._timerEventSubject = timerEventSubject
    }
    
    var remainingTimeString: String {
        let remainingSeconds = totalDuration - progress
        return remainingSeconds.secondsToRemainingTimeString
    }
    
    var body: some View {
        ZStack {
            Text(remainingTimeString)
            ProgressView(value: progress, total: totalDuration)
                .progressViewStyle(GaugeProgressStyle())
                .contentShape(Rectangle())
                .onReceive(timer) { timer in
                    if progress >= totalDuration {
                        timerEventSubject.send(.completed)
                        return
                    }
                    progress += 1
                }
                .onReceive(timerEventSubject) { event in
                    print("[TimerView] event: \(event)")
                    switch event {
                    case .startTimer(let totalRemainingTime):
                        totalDuration = totalRemainingTime
                        progress = 0
                    default:
                        break
                    }
                }
        }
    }
}

@Observable
class WaqtDetailCardViewModel {
    typealias Model = WaqtDetailModel
    private let dataResponse: DataResponse
    var currentWaqtType: Model.WaqtType = .waqtToStart(.fajr, "00:00")
    
    var timerEventSubject = PassthroughSubject<Model.TimerEvent, Never>()
    private var cancellable: Cancellable?
    
    init(dataResponse: DataResponse) {
        self.dataResponse = dataResponse
        observeTimerEvents()
    }
    
    private func observeTimerEvents() {
        updateCurrentWaqtTimer()
        cancellable = timerEventSubject.sink { [weak self] event in
            switch event {
            case .completed:
                self?.updateCurrentWaqtTimer()
            default:
                break
            }
        }
    }
    
    private func updateCurrentWaqtTimer() {
        let currentTime = Date().time24String
        currentWaqtType = Model.getCurrentWaqtType(from: dataResponse.timings, currentTime: currentTime)
        
        timerEventSubject.send(.startTimer(currentWaqtType.remainingTimeInSeconds(from: currentTime)))
    }
    
    var currentWaqt: Salah.Waqt {
        switch currentWaqtType {
        case let .waqtOngoing(waqt, _), let .waqtToStart(waqt, _):
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
}

struct WaqtDetailCard: View {
    @State private var viewModel: WaqtDetailCardViewModel
    
    init(viewModel: WaqtDetailCardViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack {
                HStack {
                    Image(systemName: viewModel.currentWaqt.icon)
                        .foregroundStyle(viewModel.currentWaqt.color)
                    Text(viewModel.currentWaqt.title)
                }
                Text("Ends in")
                TimerView(timerEventSubject: $viewModel.timerEventSubject)
                .frame(width: 100, height: 100)
            }
            Spacer()
            VStack {
                VStack {
                    Text(viewModel.dateSummary.gregorian)
                    Text(viewModel.dateSummary.hijri)
                }
                .padding(.init(top: 0, leading: 0, bottom: 10, trailing: 0))
                
                VStack(alignment: .leading) {
                    HStack {
                        Image(systemName: viewModel.sunriseSchedule.icon)
                            .foregroundStyle(viewModel.sunriseSchedule.color)
                        Text(viewModel.sunriseSchedule.title)
                    }
                    HStack {
                        Image(systemName: viewModel.sunsetSchedule.icon)
                            .foregroundStyle(viewModel.sunsetSchedule.color)
                        Text(viewModel.sunsetSchedule.title)
                    }
                }

            }
        }
    }
}

#Preview {
    WaqtDetailCard(
        viewModel: .init(dataResponse: .init(timings: .init(imsak: "05:02", fajr: "05:12", sunrise: "06:28", dhuhr: "12:12", asr: "16:19", sunset: "17:57", maghrib: "17:57", isha: "19:13"), date: .init(hijri: .init(date: "3-10-1439", day: "12", month: .init(en: "Shaban")), gregorian: .init(date: "8-10-12", day: "25", weekday: .init(en: "Sunday"), month: .init(en: "February"))))))
}
