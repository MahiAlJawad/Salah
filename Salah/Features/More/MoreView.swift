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

                MoreSectionHeader("Prayer & Reminders")
                MoreSectionCard {
                    NavigationLink { RemindersView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Prayer Reminders",
                            subtitle: "Timings, alerts & notifications",
                            symbol: "bell",
                            iconTint: .blue.opacity(0.76),
                            iconBackground: .blue.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Location & Calculation")
                MoreSectionCard {
                    NavigationLink { LocationView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Location",
                            subtitle: container.localizedLocationName,
                            symbol: "location",
                            iconTint: .blue.opacity(0.76),
                            iconBackground: .blue.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { CalculationView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Calculation Method",
                            subtitle: container.settings.calculation.method.title,
                            symbol: "slider.horizontal.3",
                            iconTint: .indigo.opacity(0.76),
                            iconBackground: .indigo.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { AdjustmentsView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Adjustments",
                            subtitle: "Manual time adjustments",
                            symbol: "clock.arrow.circlepath",
                            iconTint: .teal.opacity(0.76),
                            iconBackground: .teal.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Appearance")
                MoreSectionCard {
                    NavigationLink { AppearanceView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Display & Theme",
                            subtitle: "Mode, colors & fonts",
                            symbol: "paintpalette",
                            iconTint: .indigo.opacity(0.68),
                            iconBackground: .indigo.opacity(0.07)
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { LanguageSettingsView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Language",
                            subtitle: container.settings.language.selectorTitle,
                            symbol: "globe",
                            iconTint: .blue.opacity(0.76),
                            iconBackground: .blue.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Giving & Charity")
                MoreSectionCard {
                    NavigationLink { CharityHistoryView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Sadaqah",
                            subtitle: "A private giving intention",
                            symbol: "gift",
                            iconTint: .pink.opacity(0.76),
                            iconBackground: .pink.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)
                }

                MoreSectionHeader("Privacy & Support")
                MoreSectionCard {
                    NavigationLink { PrivacyView(container: container) } label: {
                        MoreSettingsRow(
                            title: "Privacy & Data",
                            subtitle: "Local-first and transparent",
                            symbol: "lock",
                            iconTint: .teal.opacity(0.76),
                            iconBackground: .teal.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { AboutView() } label: {
                        MoreSettingsRow(
                            title: "About Salah",
                            subtitle: "Charitable and open source",
                            symbol: "info.circle",
                            iconTint: .indigo.opacity(0.76),
                            iconBackground: .indigo.opacity(0.09)
                        )
                    }
                    .buttonStyle(.plain)

                    MoreRowDivider()

                    NavigationLink { ContactUsView() } label: {
                        MoreSettingsRow(
                            title: "Support & Contact",
                            subtitle: "Contact the project maintainer",
                            symbol: "headphones",
                            iconTint: .orange.opacity(0.76),
                            iconBackground: .orange.opacity(0.09)
                        )
                    }
                        .buttonStyle(.plain)
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
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.caption.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
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
    let iconTint: Color?
    let iconBackground: Color?

    init(
        title: String,
        subtitle: String,
        symbol: String,
        iconTint: Color? = nil,
        iconBackground: Color? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.iconTint = iconTint
        self.iconBackground = iconBackground
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(iconTint ?? palette.accentForeground)
                .frame(width: 40, height: 40)
                .background(iconBackground ?? palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
