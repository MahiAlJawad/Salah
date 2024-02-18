//
//  ContentView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 18/2/24.
//

import SwiftUI
import Foundation

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            
            Text("02/12/15, 6:35 PM".time24String)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
