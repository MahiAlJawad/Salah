//
//  TimingsView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 23/2/24.
//

import SwiftUI

struct TimingsView: View {
    @Bindable private var viewModel: TimingsViewModel

    init(viewModel: TimingsViewModel) {
        self.viewModel = viewModel
    }
    
    private func loadedListView(with data: DataResponse) -> some View {
        List {
            Section {
                TabView(selection: $viewModel.selectedCard) {
                    WaqtDetailCard(viewModel: .init(dataResponse: data, waqtUpdater: viewModel.waqtUpdater))
                        .tag(0)
                        .scaleEffect(viewModel.waqtDetailCardScaleValue)
                        .animation(.default, value: viewModel.waqtDetailCardScaleValue)
                    
                    WaqtDetailCard(viewModel: .init(dataResponse: data, waqtUpdater: viewModel.waqtUpdater))
                        .tag(1)
                        .scaleEffect(viewModel.fastingCardScaleValue)
                        .animation(.default, value: viewModel.fastingCardScaleValue)
                }
                .tabViewStyle(.page)
                .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
                .frame(height: 200)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            .padding([.bottom, .top])
            
            Section {
                ForEach(Salah.Waqt.allCases) { waqt in
                    SalahView(salah: .init(waqt: waqt, timingData: data.timings, cautionDelay: .IslamicFoundation))
                        .listRowBackground(waqt == viewModel.currentWaqt ? Color.green.opacity(0.3) : Color.clear)
                }
            }
        }
        .listStyle(.plain)
    }
    
    var body: some View {
        switch viewModel.dataResponse {
        case .loaded(let data):
            loadedListView(with: data)
                .navigationTitle(TabBarModel.Item.timings.title)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.showCalendar = true
                        } label: {
                            HStack {
                                Image(systemName: "calendar")
                                Text(viewModel.selectedDate, style: .date)
                            }
                        }
                        .popover(isPresented: $viewModel.showCalendar) {
                            DatePicker("Select date", selection: $viewModel.selectedDate, displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .padding()
                                .frame(width: 365, height: 365)
                                .presentationCompactAdaptation(.popover)
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
                .onChange(of: viewModel.selectedDate) { viewModel.showCalendar = false }
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
