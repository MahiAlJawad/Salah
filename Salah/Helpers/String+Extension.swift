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
    var time12String: Self {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = dateFormatter.date(from: self) else {
            return "Invalid Time String"
        }
        dateFormatter.dateFormat = "hh:mm a"
        return dateFormatter.string(from: date)
    }
    
    // Converts 12-hour format to 24-hour format
    // Input: 10:15 PM
    // Output: 22:15
    var time24String: Self {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "hh:mm a"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = dateFormatter.date(from: self) else {
            return "Invalid Time String"
        }
        dateFormatter.dateFormat = "HH:mm"
        return dateFormatter.string(from: date)
    }
    
    func addMinits(_ minits: Int) -> Self {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard var date = dateFormatter.date(from: self) else {
            return "Invalid Time String"
        }
        date.addTimeInterval(TimeInterval(minits * 60))
        
        return dateFormatter.string(from: date)
    }
    
    func subtractMinits(_ minits: Int) -> Self {
        addMinits(-minits)
    }
}
