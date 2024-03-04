//
//  TimingsView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 23/2/24.
//

import SwiftUI

struct TimingsView: View {
    @Bindable private var viewModel: TimingsViewModel
    @State private var selectedCard: Int = 0
    @State private var showCalendar: Bool = false
    
    init(viewModel: TimingsViewModel) {
        self.viewModel = viewModel
    }
    
    var body: some View {
        switch viewModel.dataResponse {
        case .loaded(let data):
            List {
                Section {
                    TabView(selection: $selectedCard) {
                        WaqtDetailCard(viewModel: .init(dataResponse: data))
                            .padding()
                            .tag(0)
                        WaqtDetailCard(viewModel: .init(dataResponse: data))
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
                        SalahView(salah: .init(waqt: waqt, timingData: data.timings, cautionDelay: .IslamicFoundation))
                    }
                }
            }
            .navigationTitle(TabBarModel.Item.timings.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCalendar = true
                    } label: {
                        HStack {
                            Image(systemName: "calendar")
                            Text(viewModel.selectedDate, style: .date)
                        }
                    }
                    .popover(isPresented: $showCalendar) {
                        DatePicker("Select date", selection: $viewModel.selectedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .frame(width: 400, height: 400)
                            .padding([.leading, .trailing])
                            .presentationDetents([.height(400)])
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
            .onChange(of: viewModel.selectedDate) { showCalendar = false }
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
