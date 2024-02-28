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
    var dataResponse: LoadingState<DataResponse> = .loading
    var selectedDate: Date = .now
    
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
