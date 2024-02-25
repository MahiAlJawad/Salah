//
//  TimingsView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 23/2/24.
//

import SwiftUI

struct TimingsView: View {
    @State private var viewModel: TimingsViewModel
    
    init(viewModel: TimingsViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        switch viewModel.salahTimings {
        case .loaded(let data):
            List {
                Section {
                    RemainingTimeCard()
                }
                Section {
                    ForEach(Salah.Waqt.allCases) { waqt in
                        SalahView(salah: .init(waqt: waqt, timingData: data))
                    }
                }
            }
            .navigationTitle(TabBarModel.Item.timings.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker(selection: $viewModel.selectedDate, displayedComponents: [.date]) {
                        Image(systemName: "calendar")
                    }
                }
            }
            .refreshable {
                await viewModel.loadData()
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                Task(priority: .userInitiated) {
                    await viewModel.loadData()
                }
            }
        case .loading:
            ProgressView()
                .task {
                    await viewModel.loadData()
                }
        case .failed(_):
            ContentUnavailableView(
                "Connection issue",
                systemImage: "wifi.slash",
                description: Text("Check your internet connection")
            )
        }
    }
         
}
