//
//  FastingCard.swift
//  Salah
//
//  Created by Mahi Al Jawad on 9/3/24.
//
/*

import SwiftUI

struct FastingCard: View {
    var waqtTimerView: some View {
        VStack {
            Text("Sahri")
                .font(.title2)
                .fontWeight(.bold)
            Text("Time ends in")
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
    FastingCard()
}
*/
