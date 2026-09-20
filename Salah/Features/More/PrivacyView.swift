import SwiftUI

struct PrivacyView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var showingClearConfirmation = false
    @State private var cleared = false

    var body: some View {
        List {
            Section {
                Label {
                    Text("Privacy by design")
                } icon: {
                    privacyIcon("lock", tint: .teal, background: .teal)
                }
                .font(.title3.bold())
                Text("Salah collects the minimum information required for prayer timings and remains useful when optional permissions are declined.")
            }
            Section("How Data Is Used") {
                privacyRow("Location", detail: "Prayer times are calculated on this device. Current-location requests and nearby mosque searches run only while you use the app and are processed by Apple Maps. Salah does not track location in the background or operate a location server.", symbol: "location.fill", tint: .blue, background: .blue)
                privacyRow("Prayer tracking", detail: "Completion records and notes stay entirely on your device and are never sent elsewhere.", symbol: "checkmark.circle.fill", tint: .teal, background: .teal)
                privacyRow("Notifications", detail: "Optional reminders are scheduled locally. No marketing notification service is used.", symbol: "bell.fill", tint: .blue, background: .blue)
                privacyRow("Advertising and analytics", detail: "The app contains no advertising identifier, tracking SDK, or unnecessary analytics.", symbol: "eye.slash.fill", tint: .indigo, background: .indigo)
            }
            if let privacyPolicyURL = ExternalLinks.privacyPolicy {
                Section {
                    Link("Privacy Policy", destination: privacyPolicyURL)
                }
            }
            Section {
                Button("Clear Local Tracker Data", role: .destructive) { showingClearConfirmation = true }
                if cleared { Label("Tracker data cleared", systemImage: "checkmark.circle.fill").foregroundStyle(palette.accent) }
            } header: {
                Text("Your Data")
            } footer: {
                Text("Prayer-time cache and lightweight preferences can be replaced automatically; tracker deletion cannot be undone.")
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
        .confirmationDialog("Clear all tracker data?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear Tracker Data", role: .destructive) {
                try? container.trackingRepository.clearAll()
                try? container.trackerHistoryRepository.clearAll()
                UserDefaults.standard.set(0, forKey: "salah.deeds.istighfar-count")
                UserDefaults.standard.set(0, forKey: "salah.deeds.tasbih-goal")
                UserDefaults.standard.removeObject(forKey: "salah.deeds.tasbih-day")
                UserDefaults.standard.removeObject(forKey: TasbihHistoryLedger.storageKey)
                UserDefaults.standard.set(0, forKey: "salah.deeds.good-deeds-mask")
                UserDefaults.standard.removeObject(forKey: "salah.deeds.good-deeds-day")
                UserDefaults.standard.removeObject(forKey: NaflHistoryLedger.storageKey)
                UserDefaults.standard.set(0, forKey: "salah.deeds.charity-total")
                UserDefaults.standard.removeObject(forKey: CharityLedger.storageKey)
                cleared = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently removes prayer, Tasbih, good deeds, and charity history stored on this device.")
        }
    }

    private func privacyRow(_ title: String, detail: String, symbol: String, tint: Color, background: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.dynamic(title)).font(.headline)
                Text(L10n.dynamic(detail)).font(.subheadline).foregroundStyle(.secondary)
            }
        } icon: {
            privacyIcon(symbol, tint: tint, background: background)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func privacyIcon(_ symbol: String, tint: Color, background: Color) -> some View {
        Image(systemName: symbol)
            .font(.headline)
            .foregroundStyle(tint.opacity(0.76))
            .frame(width: 40, height: 40)
            .background(background.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)
    }
}
