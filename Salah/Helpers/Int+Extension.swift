//
//  Int+Extension.swift
//  Salah
//
//  Created by Mahi Al Jawad on 25/2/24.
//

import Foundation

extension Int {
    var twoDigitString: String {
        if (self/10) > 0 {
            return "\(self)"
        } else {
            return "0\(self)"
        }
    }
}
