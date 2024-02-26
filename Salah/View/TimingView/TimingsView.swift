//
//  TimingsView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 23/2/24.
//

import SwiftUI

struct TimingsView: View {
    @State private var viewModel: TimingsViewModel
    @State var selectedCard: Int = 0
    init(viewModel: TimingsViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        switch viewModel.salahTimings {
        case .loaded(let data):
            List {
                Section {
                    TabView(selection: $selectedCard) {
                        RemainingTimeCard()
                            .padding()
                            .tag(0)
                        RemainingTimeCard()
                            .padding()
                            .tag(1)
                    }
                    .tabViewStyle(.page)
                    .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(selectedCard == 0 ? LinearGradient(colors: [.green, .teal, .blue], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(colors: [.orange, .yellow, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
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
