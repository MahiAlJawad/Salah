import SwiftUI

private struct OnboardingPage: Identifiable {
    let id: Int
    let symbol: String
    let title: String
    let body: String
}

struct OnboardingFlow: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var page = 0
    @State private var showingLocationEducation = false

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(id: 0, symbol: "clock.badge.checkmark", title: L10n.string("Prayer times at a glance"), body: L10n.string("See today’s prayer windows, the next prayer, and a calm live countdown.")),
            OnboardingPage(id: 1, symbol: "checklist", title: L10n.string("Track privately"), body: L10n.string("Record daily prayers and view supportive history. Your tracker stays on this device.")),
            OnboardingPage(id: 2, symbol: "moon.stars", title: L10n.string("Fasting and optional reminders"), body: L10n.string("See Sahri and Iftar times. Enable only the reminders that are useful to you."))
        ]
    }

    var body: some View {
        if showingLocationEducation {
            LocationEducationView(container: container)
        } else {
            VStack(spacing: 24) {
                TabView(selection: $page) {
                    ForEach(pages) { page in
                        VStack(spacing: 26) {
                            Image(systemName: page.symbol)
                                .font(.system(size: 72, weight: .medium))
                                .foregroundStyle(palette.accent)
                                .frame(width: 150, height: 150)
                                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 42))
                                .accessibilityHidden(true)
                            Text(page.title)
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                            Text(page.body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal)
                        .tag(page.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(L10n.dynamic(page == pages.count - 1 ? "Choose Prayer Location" : "Continue")) {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        showingLocationEducation = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }
}
