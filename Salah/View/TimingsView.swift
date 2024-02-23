//
//  TimingsView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 23/2/24.
//

import SwiftUI

struct TimingsView: View {
    @State var selectedDate: Date = .now
    @State var apiResponse: APIResponse?
    
    var timings: TimingResponse? {
        guard let apiResponse else { return nil }
        
        return apiResponse.data.timings
    }
    var body: some View {
        VStack {
            DatePicker(
                selection: $selectedDate,
                displayedComponents: .date
            ) {
                HStack {
                    Image(systemName: "calendar")
                    Text("Selected date")
                }
            }
            .datePickerStyle(.compact)
            .padding(.all)
            
            List {
                if let timings {
                    HStack {
                        Image(systemName: "sunrise")
                        Text("Fajr")
                        Spacer()
                        Text(timings.fajr)
                    }
                    HStack {
                        Image(systemName: "sunrise")
                        Text("Dhuhr")
                        Spacer()
                        Text(timings.dhuhr)
                    }
                    HStack {
                        Image(systemName: "sunrise")
                        Text("Asr")
                        Spacer()
                        Text(timings.asr)
                    }
                    HStack {
                        Image(systemName: "sunrise")
                        Text("Maghrib")
                        Spacer()
                        Text(timings.maghrib)
                    }
                    HStack {
                        Image(systemName: "sunrise")
                        Text("Isha")
                        Spacer()
                        Text(timings.isha)
                    }
                }
            }
        }
        .navigationTitle(TabBarModel.Item.timings.title)
        .task {
            apiResponse = await SalahAPIManager().salahTimeResponse(of: selectedDate)
        }
        .refreshable {
            apiResponse = await SalahAPIManager().salahTimeResponse(of: selectedDate)
        }
        .onChange(of: selectedDate) { _, newValue in
            Task(priority: .userInitiated) {
                apiResponse = await SalahAPIManager().salahTimeResponse(of: selectedDate)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TimingsView()
    }
}
