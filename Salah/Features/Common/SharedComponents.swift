import SwiftUI

struct SalahCard<Content: View>: View {
    var isTransparent = false
    @ViewBuilder var content: Content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    var body: some View {
        if isTransparent {
            cardContent
        } else if #available(iOS 26.0, *) {
            cardContent
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            cardContent
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.separator.opacity(0.35), lineWidth: 0.5)
                }
        }
    }
}

struct StatusBadge: View {
    let text: String
    let symbol: String
    var tint: Color?
    @Environment(\.salahPalette) private var palette

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(tint ?? palette.accent)
            .background(palette.accentSoft, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct PrayerDataUnavailableView: View {
    let error: PrayerDataError
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Prayer times unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button("Try Again") { Task { await retry() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

struct OfflineBanner: View {
    let lastUpdated: Date

    var body: some View {
        Label {
            Text("Offline · Cached \(lastUpdated.formatted(.dateTime.hour().minute().locale(L10n.locale)))")
        } icon: {
            Image(systemName: "wifi.slash")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: Capsule())
        .accessibilityLabel("Offline. Showing cached prayer times updated \(lastUpdated.formatted(.dateTime.locale(L10n.locale)))")
    }
}

struct PrayerIcon: View {
    let prayer: PrayerType
    var active = false
    @Environment(\.salahPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let semanticColor = prayer.iconTone.color(for: colorScheme)
        Image(systemName: prayer.symbol)
            .font(.headline)
            .foregroundStyle(active ? .white : semanticColor)
            .frame(width: 40, height: 40)
            .background(active ? palette.accent : semanticColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

struct TrackerSymbolIcon: View {
    let symbol: String
    let tone: SalahIconTone
    var active = false
    @Environment(\.salahPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let semanticColor = tone.color(for: colorScheme)
        Image(systemName: symbol)
            .font(.headline)
            .foregroundStyle(active ? .white : semanticColor)
            .frame(width: 40, height: 40)
            .background(active ? palette.accent : semanticColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityHidden(true)
    }
}

extension ShapeStyle where Self == Color {
    static var separator: Color { Color(uiColor: .separator) }
}

// MARK: - iPad Flicker Fix

extension View {
    /// Hides the tab bar only on iPhone (compact width).
    ///
    /// On iPad, `TabView` with `.sidebarAdaptable` renders navigation in a sidebar,
    /// not a bottom tab bar. Calling `.toolbar(.hidden, for: .tabBar)` on iPad
    /// triggers an unwanted animate-out / animate-in flicker every time a detail
    /// view is pushed or popped. This modifier suppresses that call on iPad while
    /// keeping the correct behaviour on iPhone.
    @ViewBuilder
    func phoneOnlyHideTabBar() -> some View {
        self.modifier(PhoneOnlyHideTabBarModifier())
    }
}

private struct PhoneOnlyHideTabBarModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .compact {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
        }
    }
}
