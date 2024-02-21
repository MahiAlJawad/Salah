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
            
            Text("23:00".subtractMinits(1))
        }
        .padding()
    }
    
//    func getDummyvalue() -> String {
//        if let url = Bundle.main.url(forResource: "Test", withExtension: "json") {
//            guard let data = try? Data(contentsOf: url) else {
//                return "FFAILED"
//            }
//            let decoder = JSONDecoder()
//            guard let data = try? decoder.decode(APIResponse.self, from: data) else {
//                return "Failed"
//            }
//            
//            return data.data.timings.isha
//            
//        }
//      
//        
//        return "Failed last"
//    }
}

#Preview {
    ContentView()
}
