//
//  String+Extension.swift
//  Salah
//
//  Created by Mahi Al Jawad on 18/2/24.
//

import Foundation

extension String {
    // Converts 24-hour format to 12-hour format
    // Input: 22:15
    // Output: 10:15 PM
    var time12String: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        guard let date = dateFormatter.date(from: self) else {
            return "Invalid Time String"
        }
        dateFormatter.dateFormat = "hh:mm a"
        return dateFormatter.string(from: date)
    }
    
    // Converts 12-hour format to 24-hour format
    // Input: 10:15 PM
    // Output: 22:15
    var time24String: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a"
        guard let date = dateFormatter.date(from: self) else {
            return "Invalid Time String"
        }
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter.string(from: date)
    }
}
