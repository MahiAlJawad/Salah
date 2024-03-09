//
//  WaqtDetailCard.swift
//  Salah
//
//  Created by Mahi Al Jawad on 25/2/24.
//

import SwiftUI
import Combine

struct WaqtDetailCard: View {
    @Bindable private var viewModel: WaqtDetailCardViewModel
    
    init(viewModel: WaqtDetailCardViewModel) {
        self.viewModel = viewModel
    }
    
    var waqtTimerView: some View {
        VStack {
            Text(viewModel.currentWaqt.title)
                .font(.title2)
                .fontWeight(.bold)
            Text(viewModel.currentWaqtType.timerIndicatorDescription)
                .font(.caption)
            TimerView(
                timerEventSubject: $viewModel.timerEventSubject,
                totalDuration: viewModel.totalWaqtDuration,
                progress: viewModel.elapsedTime,
                isWaqtOngoing: viewModel.isWaqtOngoing
            )
            .frame(width: 100, height: 100)
        }
    }
    
    var dayDescriptionView: some View {
        VStack {
            VStack {
                Text(viewModel.dateSummary.gregorian)
                    .fontWeight(.bold)
                Text(viewModel.dateSummary.hijri)
                    .fontWeight(.bold)
            }
            .padding(.init(top: 0, leading: 0, bottom: 10, trailing: 0))
            
            VStack {
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
    
    var body: some View {
        HStack(alignment: .center) {
            if viewModel.showTimer {
                waqtTimerView
                Spacer()
            }
            dayDescriptionView
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(viewModel.currentWaqt.backgroundCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8.0))
        .padding()
    }
}

#Preview {
    WaqtDetailCard(
        viewModel: .init(dataResponse: .init(timings: .init(imsak: "05:02", fajr: "05:12", sunrise: "06:28", dhuhr: "12:12", asr: "16:14", sunset: "17:30", maghrib: "17:57", isha: "19:13"), date: .init(hijri: .init(date: "3-10-1439", day: "12", month: .init(en: "Shaban")), gregorian: .init(date: "09-03-2024", day: "25", weekday: .init(en: "Sunday"), month: .init(en: "February")))), waqtUpdater: .init()))
}
