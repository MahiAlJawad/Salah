//
//  SalahView.swift
//  Salah
//
//  Created by Mahi Al Jawad on 24/2/24.
//

import SwiftUI

struct SalahView: View {
    private var salah: Salah
    
    init(salah: Salah) {
        self.salah = salah
    }
    
    var body: some View {
        HStack {
            Image(systemName: salah.waqt.icon)
                .foregroundStyle(salah.waqt.color)
                .padding(.trailing)
            VStack(alignment: .leading) {
                Text(salah.waqt.title)
                Text("\(salah.startingTime) - \(salah.endingTime)")
            }
        }
    }
}
