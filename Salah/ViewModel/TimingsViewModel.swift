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
    
    var selectedCard: Int = 0
    var showCalendar: Bool = false
    
    var waqtDetailCardScaleValue: CGFloat {
        selectedCard == 0 ? 1.0 : 0.7
    }
    
    var fastingCardScaleValue: CGFloat {
        selectedCard == 1 ? 1.0 : 0.7
    }
    
    init(salahAPIManager: SalahAPIManager) {
        self.salahAPIManager = salahAPIManager
    }
    
    @MainActor
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
