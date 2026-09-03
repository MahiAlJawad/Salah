import SwiftUI

struct MoreView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    #if DEBUG
    @State private var showingDebugDrawer = false
    #endif

    var body: some View {
        List {
            Text("More")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Section {
                NavigationLink { RemindersView(container: container) } label: {
                    settingsLabel("Prayer Reminders", subtitle: "Optional local notifications", symbol: "bell.fill", tint: .orange)
                }
                NavigationLink { LocationView(container: container) } label: {
                    settingsLabel("Location", subtitle: container.localizedLocationName, symbol: "location.fill", tint: .blue)
                }
                NavigationLink { CalculationView(container: container) } label: {
                    settingsLabel("Calculation", subtitle: container.settings.calculation.method.title, symbol: "function", tint: .green)
                }
                NavigationLink { AppearanceView(container: container) } label: {
                    settingsLabel("Appearances & Theme", subtitle: "Display mode and colors", symbol: "paintpalette.fill", tint: palette.accent)
                }
                NavigationLink { LanguageSettingsView(container: container) } label: {
                    settingsLabel("Language", subtitle: container.settings.language.selectorTitle, symbol: "character.bubble.fill", tint: .indigo)
                }
                NavigationLink { CharityHistoryView(container: container) } label: {
                    settingsLabel("Sadaqah", subtitle: "A private giving intention", symbol: "heart.fill", tint: .pink)
                }
            }

            Section {
                NavigationLink { PrivacyView(container: container) } label: {
                    settingsLabel("Privacy & Data", subtitle: "Local-first and transparent", symbol: "hand.raised.fill", tint: palette.accent)
                }
                NavigationLink { AboutView() } label: {
                    settingsLabel("About Salah", subtitle: "Charitable and open source", symbol: "info.circle.fill", tint: .purple)
                }
                if let supportURL = ExternalLinks.support {
                    Link(destination: supportURL) {
                        settingsLabel("Support & Contact", subtitle: "Contact the project maintainer", symbol: "person.crop.circle.fill", tint: .teal)
                    }
                }
            }

            Section {
                #if DEBUG
                LabeledContent("Version", value: versionText)
                    .onTapGesture(count: 5) { showingDebugDrawer = true }
                #else
                LabeledContent("Version", value: versionText)
                #endif
            } footer: {
                Text("Salah is free, has no advertising, and does not require an account.")
            }
        }
        .navigationTitle("More")
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .sheet(isPresented: $showingDebugDrawer) {
            DebugDrawerView(container: container)
                .presentationDetents([.medium])
        }
        #endif
    }

    private func settingsLabel(_ title: String, subtitle: String, symbol: String, tint: Color) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).foregroundStyle(.primary)
                Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(minHeight: 44)
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}
