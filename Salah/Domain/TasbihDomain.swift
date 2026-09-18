import Foundation

enum NaflPractice: Int, CaseIterable, Codable, Identifiable, Sendable {
    case tahajjud
    case ishrak
    case morningAdhkar
    case eveningAdhkar
    case quran

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .tahajjud: L10n.string("Prayed Tahajjud")
        case .ishrak: L10n.string("Prayed Ishrak")
        case .morningAdhkar: L10n.string("Morning Adhkar")
        case .eveningAdhkar: L10n.string("Evening Adhkar")
        case .quran: L10n.string("Read Quran")
        }
    }

    var symbol: String {
        switch self {
        case .tahajjud: "moon.stars.fill"
        case .ishrak: "sunrise.fill"
        case .morningAdhkar: "sun.horizon.fill"
        case .eveningAdhkar: "sunset.fill"
        case .quran: "book.closed.fill"
        }
    }

    var iconTone: SalahIconTone {
        switch self {
        case .tahajjud: .midnightViolet
        case .ishrak, .morningAdhkar: .sunriseAmber
        case .eveningAdhkar: .sunsetCoral
        case .quran: .quranEmerald
        }
    }
}

struct TasbihDailyRecord: Codable, Equatable, Identifiable, Sendable {
    var day: LocalDay
    var count: Int
    var goal: Int
    var updatedAt: Date

    var id: String { day.key }
}

enum TasbihHistoryLedger {
    static func totalCount(_ records: [TasbihDailyRecord]) -> Decimal {
        records.reduce(Decimal.zero) { $0 + Decimal($1.count) }
    }

    static let storageKey = "salah.deeds.tasbih-history.v1"

    static func decode(_ data: Data) -> [TasbihDailyRecord] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([TasbihDailyRecord].self, from: data)) ?? []
    }

    static func encode(_ records: [TasbihDailyRecord]) -> Data {
        (try? JSONEncoder().encode(records.sorted { $0.day < $1.day })) ?? Data()
    }

    static func recording(count: Int, goal: Int, on day: LocalDay, in data: Data) -> Data {
        var records = decode(data)
        if let index = records.firstIndex(where: { $0.day == day }) {
            records[index].count = max(0, count)
            records[index].goal = max(0, goal)
            records[index].updatedAt = .now
        } else {
            records.append(TasbihDailyRecord(day: day, count: max(0, count), goal: max(0, goal), updatedAt: .now))
        }
        return encode(records)
    }

    static func incrementing(goal: Int, on day: LocalDay, in data: Data) -> Data {
        let current = decode(data).first(where: { $0.day == day })?.count ?? 0
        return recording(count: current + 1, goal: goal, on: day, in: data)
    }
}

struct NaflDailyRecord: Codable, Equatable, Identifiable, Sendable {
    var day: LocalDay
    var completedMask: Int
    var updatedAt: Date

    var id: String { day.key }
    var completedCount: Int {
        NaflPractice.allCases.filter { completedMask & (1 << $0.rawValue) != 0 }.count
    }

    func contains(_ practice: NaflPractice) -> Bool {
        completedMask & (1 << practice.rawValue) != 0
    }
}

enum NaflHistoryLedger {
    static let storageKey = "salah.deeds.nafl-history.v1"

    static func decode(_ data: Data) -> [NaflDailyRecord] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([NaflDailyRecord].self, from: data)) ?? []
    }

    static func encode(_ records: [NaflDailyRecord]) -> Data {
        (try? JSONEncoder().encode(records.sorted { $0.day < $1.day })) ?? Data()
    }

    static func recording(mask: Int, on day: LocalDay, in data: Data) -> Data {
        var records = decode(data)
        if let index = records.firstIndex(where: { $0.day == day }) {
            records[index].completedMask = max(0, mask)
            records[index].updatedAt = .now
        } else {
            records.append(NaflDailyRecord(day: day, completedMask: max(0, mask), updatedAt: .now))
        }
        return encode(records)
    }
}

/// Accepts localized decimal digits, but never signs, fractions, or overflowing totals.
enum TasbihTotalInput {
    static func parse(_ text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var digits = ""
        for character in text {
            guard character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }),
                  let value = character.wholeNumberValue, value < 10 else { return nil }
            digits.append(String(value))
        }
        return Int(digits)
    }
}
