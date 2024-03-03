//
//  TimerView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 3/3/24.
//

import SwiftUI
import Combine

struct TimerView: View {
    @State private var totalDuration: Double
    @State private var progress: Double
    @State var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    @Binding private var timerEventSubject: PassthroughSubject<WaqtDetailModel.TimerEvent, Never>
    @State private var isWaqtOngoing: Bool
    
    init(
        timerEventSubject: Binding<PassthroughSubject<WaqtDetailModel.TimerEvent, Never>>,
        totalDuration: Double,
        progress: Double,
        isWaqtOngoing: Bool
    ) {
        self._timerEventSubject = timerEventSubject
        self.totalDuration = totalDuration
        self.progress = progress
        self.isWaqtOngoing = isWaqtOngoing
    }
    
    var remainingTimeString: String {
        let remainingSeconds = totalDuration - progress
        return remainingSeconds.secondsToRemainingTimeString
    }
    
    var body: some View {
        ZStack {
            Text(remainingTimeString)
            ProgressView(value: progress, total: totalDuration)
                .progressViewStyle(GaugeProgressStyle( isWaqtOngoing: $isWaqtOngoing))
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
                    case .startTimer(let totalRemainingTime, let elapsedTime, let isWaqtOngoing):
                        totalDuration = totalRemainingTime
                        progress = elapsedTime
                        self.isWaqtOngoing = isWaqtOngoing
                    default:
                        break
                    }
                }
                .onAppear {
                    timerEventSubject.send(.refresh)
                }
        }
    }
}


struct GaugeProgressStyle: ProgressViewStyle {
    var remainingStrokeColor: Color {
        isWaqtOngoing ? .blue : .secondary.opacity(0.5)
    }
    
    var strokeColor: Color {
        isWaqtOngoing ? .secondary.opacity(0.5) : .blue
    }
    
    var strokeWidth = 10.0
    
    @Binding var isWaqtOngoing: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        let fractionCompleted = configuration.fractionCompleted ?? 0
        
        return ZStack {
            Circle()
                .trim(from: fractionCompleted, to: 1)
                .stroke(remainingStrokeColor, style: StrokeStyle(lineWidth: strokeWidth))
                .rotationEffect(.degrees(-90))
            Circle()
                .trim(from: 0, to: fractionCompleted)
                .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth))
                .rotationEffect(.degrees(-90))
        }
    }
}
