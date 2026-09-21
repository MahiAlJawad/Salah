import SwiftUI

struct PrivacyView: View {
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
                privacyRow("Prayer tracking", detail: "Completion records and notes sync through your private iCloud database so they are available on your devices. Salah does not operate a tracker-data server.", symbol: "checkmark.circle.fill", tint: .teal, background: .teal)
                privacyRow("Notifications", detail: "Optional reminders are scheduled locally. No marketing notification service is used.", symbol: "bell.fill", tint: .blue, background: .blue)
                privacyRow("Advertising and analytics", detail: "The app contains no advertising identifier, tracking SDK, or unnecessary analytics.", symbol: "eye.slash.fill", tint: .indigo, background: .indigo)
            }
            if let privacyPolicyURL = ExternalLinks.privacyPolicy {
                Section {
                    Link("Privacy Policy", destination: privacyPolicyURL)
                }
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
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
