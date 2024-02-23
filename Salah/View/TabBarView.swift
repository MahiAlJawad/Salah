//
//  TabBarView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 23/2/24.
//

import SwiftUI

struct TabBarView: View {
    typealias Tab = TabBarModel.Item
    
    @State var selectedTab: Tab = .timings
    
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                TimingsView()
            }
            .tabItem {
                Label(Tab.timings.title, systemImage: Tab.timings.icon)
            }
            .tag(Tab.timings)
            
            Text("Coming Soon")
                .tabItem {
                    Label(Tab.tracker.title, systemImage: Tab.tracker.icon)
                }
                .tag(Tab.tracker)
            
            Text("Coming Soon")
                .tabItem {
                    Label(Tab.more.title, systemImage: Tab.more.icon)
                }
                .tag(Tab.more)
        }
    }
}

#Preview {
    TabBarView()
}
