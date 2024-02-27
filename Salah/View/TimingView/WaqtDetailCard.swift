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
    let totalDuration: Double = 3600
    @State private var progress: Double = 400
    @State var timer = Timer.publish(every: 1, on: .main, in: .common)
    
    @State var cancellable: Cancellable?
    
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
                    print("Timer: \(timer)")
                    if progress >= totalDuration {
                        cancellable?.cancel()
                        return
                    }
                    progress += 1
                }
        }
    }
}

@Observable
class WaqtDetailCardModel {
    var timingResponse: TimingResponse
    
    var sunriseSchedule: SunSchedules {
        SunSchedules.sunrise(timingResponse.sunrise)
    }
    
    var sunsetSchedule: SunSchedules {
        SunSchedules.sunset(timingResponse.sunrise)
    }
    
    init(timingResponse: TimingResponse) {
        self.timingResponse = timingResponse
    }
}

struct WaqtDetailCard: View {
    var viewModel: WaqtDetailCardModel = .init(
        timingResponse: .init(imsak: "05:02", fajr: "05:12", sunrise: "06:28", dhuhr: "12:12", asr: "16:19", sunset: "17:57", maghrib: "17:57", isha: "19:13")
    )
    
    var body: some View {
        HStack(alignment: .center) {
            VStack {
                HStack {
                    Image(systemName: "sun.horizon.fill")
                        .foregroundStyle(.red)
                    Text("Magrib")
                }
                Text("Ends in")
                TimerView()
                    .frame(width: 100, height: 100)
            }
            Spacer()
            VStack {
                VStack {
                    Text("Sunday, 25 February")
                    Text("14 Shaban, 1439")
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
        viewModel: .init(
            timingResponse: .init(imsak: "05:02", fajr: "05:12", sunrise: "06:28", dhuhr: "12:12", asr: "16:19", sunset: "17:57", maghrib: "17:57", isha: "19:13")
        )
    )
}
