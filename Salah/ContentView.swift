//
//  ContentView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 18/2/24.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State var apiResponse: APIResponse?
    
    var ishaTime: String {
        guard let apiResponse else { return ""}
        return apiResponse.data.timings.isha
    }
    
    var body: some View {
        Text(ishaTime)
    }
}

#Preview {
    ContentView()
}
