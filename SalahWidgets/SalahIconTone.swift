import SwiftUI

enum SalahIconTone: String, CaseIterable, Hashable, Sendable {
    case midnightViolet
    case predawnIndigo
    case sunriseAmber
    case noonGold
    case afternoonOrange
    case sunsetCoral
    case nightBlue
    case quranEmerald

    func color(for colorScheme: ColorScheme) -> Color {
        let components = colorScheme == .dark ? darkComponents : lightComponents
        return Color(
            red: components.red / 255,
            green: components.green / 255,
            blue: components.blue / 255
        )
    }

    var darkSurfaceColor: Color {
        let components = darkComponents
        return Color(
            red: components.red / 255,
            green: components.green / 255,
            blue: components.blue / 255
        )
    }

    private var lightComponents: (red: Double, green: Double, blue: Double) {
        switch self {
        case .midnightViolet: (0x72, 0x51, 0xA6)
        case .predawnIndigo: (0x57, 0x66, 0xA6)
        case .sunriseAmber: (0xA0, 0x5A, 0x00)
        case .noonGold: (0x95, 0x65, 0x00)
        case .afternoonOrange: (0xB9, 0x4F, 0x00)
        case .sunsetCoral: (0xB6, 0x3C, 0x3C)
        case .nightBlue: (0x2D, 0x55, 0x96)
        case .quranEmerald: (0x21, 0x7A, 0x55)
        }
    }

    private var darkComponents: (red: Double, green: Double, blue: Double) {
        switch self {
        case .midnightViolet: (0xC8, 0xA7, 0xF0)
        case .predawnIndigo: (0xAB, 0xB7, 0xFF)
        case .sunriseAmber: (0xFF, 0xB1, 0x4A)
        case .noonGold: (0xFF, 0xD3, 0x5A)
        case .afternoonOrange: (0xFF, 0x97, 0x50)
        case .sunsetCoral: (0xFF, 0x7D, 0x73)
        case .nightBlue: (0x8C, 0xB4, 0xFF)
        case .quranEmerald: (0x65, 0xD6, 0xA7)
        }
    }
}
