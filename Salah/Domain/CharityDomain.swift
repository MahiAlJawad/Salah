import Foundation

enum CharityCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case sadaqah
    case zakat
    case food
    case education
    case emergency
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .sadaqah: L10n.string("Sadaqah")
        case .zakat: L10n.string("Zakat")
        case .food: L10n.string("Food")
        case .education: L10n.string("Education")
        case .emergency: L10n.string("Emergency relief")
        case .other: L10n.string("Other")
        }
    }

    var symbol: String {
        switch self {
        case .sadaqah: "heart.fill"
        case .zakat: "moon.stars.fill"
        case .food: "takeoutbag.and.cup.and.straw.fill"
        case .education: "book.closed.fill"
        case .emergency: "cross.case.fill"
        case .other: "gift.fill"
        }
    }
}

enum CharityCurrency {
    struct Option: Identifiable, Equatable {
        let code: String
        let countryNames: [String]

        var id: String { code }
    }

    static let storageKey = "salah.deeds.charity-currency"

    static func code(for locale: Locale = .current) -> String {
        locale.currency?.identifier ?? "USD"
    }

    static func options(for locale: Locale = .current) -> [Option] {
        let countriesByCurrency = Dictionary(grouping: Locale.Region.isoRegions) { region in
            Locale(identifier: "und_\(region.identifier)").currency?.identifier
        }

        return Locale.Currency.isoCurrencies.map { currency in
            let countryNames = countriesByCurrency[currency.identifier, default: []]
                .compactMap { locale.localizedString(forRegionCode: $0.identifier) }
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return Option(code: currency.identifier, countryNames: countryNames)
        }
        .sorted { $0.code < $1.code }
    }

    static func filteredOptions(
        matching query: String,
        locale: Locale = .current
    ) -> [Option] {
        let options = options(for: locale)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return options }
        return options.filter { option in
            option.code.localizedCaseInsensitiveContains(query)
                || option.countryNames.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

struct CharityEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var amount: Double
    var date: Date
    var category: CharityCategory
    var currencyCode: String
    var recipient: String
    var note: String

    private enum CodingKeys: String, CodingKey {
        case id
        case amount
        case date
        case category
        case currencyCode
        case recipient
        case note
    }

    init(
        id: UUID = UUID(),
        amount: Double,
        date: Date,
        category: CharityCategory,
        currencyCode: String = CharityCurrency.code(),
        recipient: String = "",
        note: String = ""
    ) {
        self.id = id
        self.amount = amount
        self.date = date
        self.category = category
        self.currencyCode = currencyCode
        self.recipient = recipient
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        amount = try container.decode(Double.self, forKey: .amount)
        date = try container.decode(Date.self, forKey: .date)
        category = try container.decode(CharityCategory.self, forKey: .category)
        currencyCode = try container.decodeIfPresent(String.self, forKey: .currencyCode) ?? CharityCurrency.code()
        recipient = try container.decodeIfPresent(String.self, forKey: .recipient) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(amount, forKey: .amount)
        try container.encode(date, forKey: .date)
        try container.encode(category, forKey: .category)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(note, forKey: .note)
    }
}

enum CharityLedger {
    static let storageKey = "salah.deeds.charity-entries.v1"

    private struct CurrencyProbe: Decodable {
        let currencyCode: String?
    }

    static func decode(_ data: Data) -> [CharityEntry] {
        guard !data.isEmpty else { return [] }
        return (try? JSONDecoder().decode([CharityEntry].self, from: data)) ?? []
    }

    static func encode(_ entries: [CharityEntry]) -> Data {
        (try? JSONEncoder().encode(entries)) ?? Data()
    }

    static func needsCurrencyMigration(_ data: Data) -> Bool {
        guard let probes = try? JSONDecoder().decode([CurrencyProbe].self, from: data) else { return false }
        return probes.contains { $0.currencyCode == nil }
    }

    static func entries(
        _ entries: [CharityEntry],
        inMonthContaining date: Date,
        calendar: Calendar = .current
    ) -> [CharityEntry] {
        guard let interval = calendar.dateInterval(of: .month, for: date) else { return [] }
        return entries.filter { interval.contains($0.date) }
    }

    static func total(
        _ entries: [CharityEntry],
        inMonthContaining date: Date,
        calendar: Calendar = .current
    ) -> Double {
        self.entries(entries, inMonthContaining: date, calendar: calendar).reduce(0) { $0 + $1.amount }
    }
}
