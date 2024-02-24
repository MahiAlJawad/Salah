//
//  TimingViewModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 24/2/24.
//

import Foundation
import SwiftUI

@Observable
class TimingsViewModel {
    private var salahAPIManager: SalahAPIManager
    private var dataResponse: LoadingState<DataResponse> = .loading
    var selectedDate: Date = .now
    
    var salahTimings: LoadingState<TimingResponse> {
        switch dataResponse {
        case .loaded(let data):
            return .loaded(data.timings)
        case .loading:
            return .loading
        case .failed(let error):
            print("Error: \(error)")
            return .failed(error)
        }
    }
    
    init(salahAPIManager: SalahAPIManager) {
        self.salahAPIManager = salahAPIManager
    }
    
    func loadData() async {
        let result = await salahAPIManager.salahTimeResponse(of: selectedDate)
        
        switch result {
        case .success(let response):
            dataResponse = .loaded(response)
        case .failure(let error):
            dataResponse = .failed(error)
        }
    }
}
