import SwiftUI

struct MoreView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    #if DEBUG
    @State private var showingDebugDrawer = false
    #endif

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                titleView

                MoreSectionHeader("Prayer & Reminders", symbol: "bell")
                MoreSectionCard {
                    NavigationLink { RemindersView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Prayer Reminders",
                            subtitle: "Timings, alerts & notifications",
                            symbol: "bell"
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Location & Calculation", symbol: "location")
                MoreSectionCard {
                    NavigationLink { LocationView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Location",
                            subtitle: container.localizedLocationName,
                            symbol: "location"
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { CalculationView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Calculation Method",
                            subtitle: container.settings.calculation.method.title,
                            symbol: "function"
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { AdjustmentsView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Adjustments",
                            subtitle: "Manual time adjustments",
                            symbol: "calendar.badge.clock"
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Appearance", symbol: "paintpalette")
                MoreSectionCard {
                    NavigationLink { AppearanceView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Display & Theme",
                            subtitle: "Mode, colors & fonts",
                            symbol: "paintpalette"
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { LanguageSettingsView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Language",
                            subtitle: container.settings.language.selectorTitle,
                            symbol: "character.textbox"
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Giving & Charity", symbol: "heart")
                MoreSectionCard {
                    NavigationLink { CharityHistoryView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Sadaqah",
                            subtitle: "A private giving intention",
                            symbol: "heart"
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Privacy & Support", symbol: "shield")
                MoreSectionCard {
                    NavigationLink { PrivacyView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Privacy & Data",
                            subtitle: "Local-first and transparent",
                            symbol: "lock.shield"
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { AboutView() } label: {
                        MoreSettingsRow(
                            title: "About Salah",
                            subtitle: "Charitable and open source",
                            symbol: "info.circle"
                        )
                    }
                    .buttonStyle(.plain)

                    if let supportURL = ExternalLinks.support {
                        MoreRowDivider()

                        Link(destination: supportURL) {
                            MoreSettingsRow(
                                title: "Support & Contact",
                                subtitle: "Contact the project maintainer",
                                symbol: "headphones"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle("More")
        .toolbar(.hidden, for: .navigationBar)
        #if DEBUG
        .sheet(isPresented: $showingDebugDrawer) {
            DebugDrawerView(container: container)
                .presentationDetents([.medium])
        }
        #endif
    }

    @ViewBuilder
    private var titleView: some View {
        #if DEBUG
        Text("More")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .onTapGesture(count: 5) { showingDebugDrawer = true }
        #else
        Text("More")
            .font(.largeTitle.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

private struct MoreSectionHeader: View {
    @Environment(\.salahPalette) private var palette
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 28)
        }
        .padding(.horizontal, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct MoreSectionCard<Content: View>: View {
    @Environment(\.salahPalette) private var palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 10)
        .background(
            palette.groupedSurface,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.separator.opacity(0.25), lineWidth: 0.5)
        }
    }
}

private struct MoreSettingsRow: View {
    @Environment(\.salahPalette) private var palette
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(palette.accentForeground)
                .frame(width: 40, height: 40)
                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(LocalizedStringKey(subtitle))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MoreRowDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 68)
            .padding(.trailing, 16)
    }
}

struct AdjustmentsView: View {
    @Bindable var container: AppContainer

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Hijri adjustment: \(signed(container.settings.calculation.hijriAdjustment)) day",
                    value: calculationBinding(\.hijriAdjustment),
                    in: -2...2
                )
                Stepper(
                    "Safety adjustment: \(container.settings.calculation.cautionMinutes) min",
                    value: calculationBinding(\.cautionMinutes),
                    in: 0...10
                )
            } header: {
                Text("Adjustments")
            } footer: {
                Text("Safety adjustment ends Sahri earlier and begins Maghrib and Iftar later. Published times may differ; confirm with an appropriate local authority when necessary.")
            }
        }
        .navigationTitle("Adjustments")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
    }

    private func calculationBinding<Value>(_ keyPath: WritableKeyPath<CalculationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { container.settings.calculation[keyPath: keyPath] },
            set: { value in
                let oldSignature = PrayerTimesQuery(
                    day: container.router.selectedDay,
                    location: container.settings.location,
                    settings: container.settings.calculation
                ).signature
                var calculation = container.settings.calculation
                calculation[keyPath: keyPath] = value
                container.settings.calculation = calculation
                Task {
                    await container.prayerTimesRepository.invalidate(signature: oldSignature)
                    await ReminderCoordinator.reconcile(container: container)
                }
            }
        )
    }

    private func signed(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }
}
