//
//  APIResponseModel.swift
//  Salah
//
//  Created by Mahi Al Jawad on 21/2/24.
//

import Foundation

import Foundation

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


