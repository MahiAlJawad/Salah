import SwiftUI
import UIKit

enum ExternalLinks {
    static let privacyPolicy = URL(string: "https://salah-ios-privacy-policy.vercel.app/")
}

struct ContactUsView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.salahPalette) private var palette
    @State private var message = ""

    private var canContinue: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Have a question or feedback? Write to us.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("Your Message")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text("Write your message…")
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $message)
                        .padding(12)
                        .scrollContentBackground(.hidden)
                        .accessibilityIdentifier("contact.message")
                }
                .frame(minHeight: 250)
                .background(palette.groupedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(action: continueToEmail) {
                    Text("Continue to Email")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(canContinue ? 1 : 0.45)
                .disabled(!canContinue)
                .accessibilityIdentifier("contact.continueToEmail")

                Text("Review and send your message in the email composer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Contact Us")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
    }

    private func continueToEmail() {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "nusratjahan.iosdev@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Salah Support"),
            URLQueryItem(name: "body", value: message)
        ]

        guard let url = components.url else { return }
        openURL(url)
    }
}

struct SettingsOpener {
    let open: @MainActor () -> Void

    @MainActor
    func callAsFunction() {
        open()
    }

    static let system = SettingsOpener {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct SettingsOpenerEnvironmentKey: EnvironmentKey {
    static let defaultValue = SettingsOpener.system
}

extension EnvironmentValues {
    var settingsOpener: SettingsOpener {
        get { self[SettingsOpenerEnvironmentKey.self] }
        set { self[SettingsOpenerEnvironmentKey.self] = newValue }
    }
}
