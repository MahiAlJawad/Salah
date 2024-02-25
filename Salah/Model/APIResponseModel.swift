//
//  APIResponseModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 21/2/24.
//

import Foundation
import SwiftData

// MARK: LoadingState
enum LoadingState<Data> {
    case loaded(Data)
    case loading
    case failed(ResponseError)
}

// MARK: Errors
enum ResponseError: Error {
    case urlConvertionError
    case error(String)
}

// MARK: For Salah API Response

struct APIResponse: Codable {
    let data: DataResponse
}

struct DataResponse: Codable {
    let timings: TimingResponse
    let date: DateResponse
}

struct TimingResponse: Codable {
    let imsak: String
    let fajr: String
    let sunrise: String
    let dhuhr: String
    let asr: String
    let sunset: String
    let maghrib: String
    let isha: String
    
    enum CodingKeys: String, CodingKey {
        case imsak = "Imsak"
        case fajr = "Fajr"
        case sunrise = "Sunrise"
        case dhuhr = "Dhuhr"
        case asr = "Asr"
        case sunset = "Sunset"
        case maghrib = "Maghrib"
        case isha = "Isha"
    }
}

struct DateResponse: Codable {
    let hijri: HijriDateResponse
    let gregorian: GregorianDateResponse
}

struct HijriDateResponse: Codable {
    let date: String
}

struct GregorianDateResponse: Codable {
    let date: String
}

// MARK: For Location by City Response

struct BDLocations: Codable {
    let districts: [BDDistrict]
}

struct BDDistrict: Codable, Identifiable {
    let id = UUID()
    let name: String
    let banglaName: String
    let lat: String
    let lon: String
    
    enum CodingKeys: String, CodingKey {
        case name
        case banglaName = "bn_name"
        case lat
        case lon
    }
}
