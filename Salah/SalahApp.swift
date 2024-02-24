//
//  SalahApp.swift
//  Salah
//
//  Created by Mahi Al Jawad on 18/2/24.
//

import SwiftUI

@main
struct SalahApp: App {
    private let salahAPIManager = SalahAPIManager()
    
    var body: some Scene {
        WindowGroup {
            TabBarView(salahAPIManager: salahAPIManager)
        }
    }
}
