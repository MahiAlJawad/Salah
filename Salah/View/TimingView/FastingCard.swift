//  FastingCard.swift
//
//  Created by Mahi Al Jawad on 9/3/24.


import SwiftUI
import Combine

struct FastingCard: View {
    @Bindable var viewModel: FastingCardViewModel
    
    init(viewModel: FastingCardViewModel) {
        self.viewModel = viewModel
    }
    
    var timerView: some View {
        VStack {
            Text(viewModel.fastingEvent.type.title)
                .font(.title2)
                .fontWeight(.bold)
            Text(viewModel.fastingEvent.timerIndicatorDescription)
                .font(.caption)
            TimerView(
                timerEventSubject: $viewModel.timerEventSubject,
                totalDuration: viewModel.totalDuration,
                progress: viewModel.elapsedTime,
                isWaqtOngoing: false
            )
            .frame(width: 100, height: 100)
        }
    }
    
    var fastingScheduleView: some View {
        VStack {
            VStack {
                Text(viewModel.dateSummary.gregorian)
                    .fontWeight(.bold)
                Text(viewModel.dateSummary.hijri)
                    .fontWeight(.bold)
            }
            .padding(.init(top: 0, leading: 0, bottom: 10, trailing: 0))
            
            VStack(alignment: .trailing) {
                HStack {
                    Text(viewModel.fastingEvent.sahriLastTime)
                    Button {
                        viewModel.toggleSahriAlert()
                    } label: {
                        Image(systemName: viewModel.isSahriAlertEnabled ?  "bell.fill" : "bell")
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Text(viewModel.fastingEvent.iftarStartTime)
                    Button {
                        viewModel.toggleIftarAlert()
                    } label: {
                        Image(systemName: viewModel.isIftarAlertEnabled ?  "bell.fill" : "bell")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .center) {
            if viewModel.showTimer {
                timerView
                Spacer()
            }
            fastingScheduleView
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(viewModel.fastingEvent.type.backgroundCanvas)
        .clipShape(RoundedRectangle(cornerRadius: 8.0))
        .padding()
    }
}

#Preview {
    FastingCard(viewModel: .init(dataResponse: .init(timings: .init(imsak: "05:02", fajr: "05:12", sunrise: "06:28", dhuhr: "12:12", asr: "16:14", sunset: "18:09", maghrib: "17:57", isha: "19:13"), date: .init(hijri: .init(date: "3-10-1439", day: "12", month: .init(en: "Shaban")), gregorian: .init(date: "10-03-2024", day: "25", weekday: .init(en: "Sunday"), month: .init(en: "February"))))))
}
