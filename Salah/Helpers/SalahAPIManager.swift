//
//  SalahAPIManager.swift
//  Salah
//
//  Created by Mahi Al Jawad on 22/2/24.
//

import Foundation

class SalahAPIManager {
    private var dateResponse: [String: DataResponse] = [:]
    
    func salahTimeResponse(
        of date: Date = Date(),
        location: Location = .coordinate(lat: 23.7115253, lon: 90.4111451),
        method: Method = .UIS_Karachi,
        cautionDelay: CautionDelay = .IslamicFoundation,
        madhab: Madhab = .hanafi,
        hijriDateAdjustment: HijriDateAdjustment = .adjustDays(-1)
    ) async -> Result<DataResponse, ResponseError> {
        if let response = dateResponse[date.dateString] {
            print("Returning from cache")
            return .success(response)
        }
        
        guard let url = getURL(
            date: date,
            location: location,
            method: method,
            cautionDelay: cautionDelay,
            madhab: madhab,
            hijriDateAdjustment: hijriDateAdjustment
        ) else {
            print("Failed getting URL")
            return .failure(.urlConvertionError)
        }
        print("Fetching data")
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let salahAPIResponse = try JSONDecoder().decode(APIResponse.self, from: data)
            dateResponse[date.dateString] = salahAPIResponse.data
            return .success(salahAPIResponse.data)
        } catch {
            print("Error: \(error)")
            return .failure(.error(error.localizedDescription))
        }
    }
    
    private func getURL(
        date: Date,
        location: Location,
        method: Method,
        cautionDelay: CautionDelay,
        madhab: Madhab,
        hijriDateAdjustment: HijriDateAdjustment
    ) -> URL? {
        var urlString: String = "https://api.aladhan.com/v1"
        
        urlString += "/timings/\(date.dateString)?latitude=\(location.lattitude)&longitude=\(location.longitude)"
        
        if method == .UIS_Karachi {
            urlString += "&method=1"
        }
        // For other methods the method will be selected by nearest location
        
        if madhab == .hanafi {
            urlString += "&school=1"
        }
        // For other madhabs default will be set in the API
        
        urlString += "&adjustment=\(hijriDateAdjustment.days)"
        urlString += "&tune=\(cautionDelay.delay)"
        
        print("URL: \(urlString)")
        
        return URL(string: urlString)
    }
    
    func getAllDistricts() -> [BDDistrict] {
        if let bdLocationsURL = Bundle.main.url(forResource: "districts", withExtension: "json") {
            guard let bdLocationsData = try? Data(contentsOf: bdLocationsURL) else {
                return []
            }
            
            guard let bdLocations = try? JSONDecoder().decode(BDLocations.self, from: bdLocationsData) else {
                return []
            }
            
            return bdLocations.districts
        }
        return []
    }
}

/*
 https://api.aladhan.com/v1/timings/22-02-2024?latitude=23.7115253&longitude=90.4111451&method=1&school=1&adjustment=-1&tune=3
 */
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
