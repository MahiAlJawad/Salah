//
//  Date+Extension.swift
//  Salah
//
//  Created by Mahi Al Jawad on 22/2/24.
//

import Foundation

extension Date {
    var dateString: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd-mm-yyyy"
        return dateFormatter.string(from: self)
    }
}
