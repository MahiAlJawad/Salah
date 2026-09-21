import MapKit
import SwiftUI

struct OnboardingFlow: View {
    /// The five obligatory prayers. Sahri and Iftar stay off during onboarding.
    private static let reminderEvents: [PrayerEvent] = PrayerEvent.allCases.filter { ![.sahri, .iftar].contains($0) }
    private static let pageCount = 3

    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @Environment(\.settingsOpener) private var settingsOpener
    @Environment(\.scenePhase) private var scenePhase

    @State private var page = 0
    @State private var today: PrayerDay?
    @State private var nextWindow: PrayerWindow?
    @State private var completedCount = 0
    @State private var camera: MapCameraPosition = .automatic
    @State private var locationError: String?
    @State private var isRequestingLocation = false
    @State private var isRequestingReminders = false
    @State private var notificationStatus: NotificationAuthorization = .notDetermined
    @State private var showingCityPicker = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { complete() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .accessibilityHint("Finishes setup without requesting permissions")
            }
            .padding(.horizontal, 20)

            TabView(selection: $page) {
                scrollingPage { overviewPage }.tag(0)
                scrollingPage { locationPage }.tag(1)
                scrollingPage { remindersPage }.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            OnboardingPageIndicator(count: Self.pageCount, current: page)
                .padding(.vertical, 14)

            actions
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .sheet(isPresented: $showingCityPicker) {
            GlobalLocationPickerView(container: container, showsCurrentLocation: false) { location in
                showingCityPicker = false
                apply(location)
            }
        }
        .task(id: previewIdentity) { await loadPreview() }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNotificationStatus() } }
        }
    }

    // MARK: - Pages

    private func scrollingPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var overviewPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Salah")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(.secondary)

            Text("Everything you need, without the noise")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 12) {
                OnboardingPreviewRow(
                    caption: L10n.string("Next prayer"),
                    value: nextPrayerTitle
                ) {
                    if let prayer = nextWindow?.prayer {
                        PrayerIcon(prayer: prayer)
                    } else {
                        TrackerSymbolIcon(symbol: "clock.fill", tone: .nightBlue)
                    }
                } detail: {
                    if let start = nextWindow?.start {
                        Text(time(start))
                    }
                }

                OnboardingPreviewRow(
                    caption: L10n.string("Track today"),
                    value: trackedTitle
                ) {
                    TrackerSymbolIcon(symbol: "checkmark.circle.fill", tone: .quranEmerald)
                }

                OnboardingPreviewRow(
                    caption: L10n.string("Qibla"),
                    value: qiblaTitle
                ) {
                    TrackerSymbolIcon(symbol: "location.north.line.fill", tone: .predawnIndigo)
                }
            }

            Text("Prayer times, tracking, Qibla, fasting, and more — designed to feel focused.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var locationPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Prayer times built around your location")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            SalahCard {
                Map(position: $camera, interactionModes: [])
                    .frame(height: 170)
                    .overlay {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(palette.accent, .white)
                            .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                Label(container.localizedLocationName, systemImage: "mappin.and.ellipse")
                    .font(.title3.bold())
                    .padding(.top, 4)

                StatusBadge(text: L10n.string("Used only when requested"), symbol: "lock.fill")

                Divider()
                    .padding(.vertical, 4)

                Text("Choose current location or search any city. You can change it anytime.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let locationError {
                Text(locationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Location error. \(locationError)")
            }
        }
    }

    private var remindersPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A gentle reminder for each Salah")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            SalahCard {
                ForEach(Self.reminderEvents) { event in
                    OnboardingReminderRow(event: event, time: today?.eventDate(event).map(time))
                    if event != Self.reminderEvents.last {
                        Divider()
                    }
                }

                StatusBadge(text: L10n.string("Scheduled on this device"), symbol: "lock.fill")
                    .padding(.top, 6)
            }

            if notificationStatus == .denied {
                Text("Notifications are turned off for this app. Turn them on in Settings to get this reminder.")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            switch page {
            case 0:
                primaryButton("Continue") { withAnimation { page = 1 } }
            case 1:
                primaryButton("Use Current Location", isBusy: isRequestingLocation) { requestCurrentLocation() }
                secondaryButton("Choose a City") { showingCityPicker = true }
            default:
                if notificationStatus == .denied {
                    primaryButton("Open settings") { settingsOpener() }
                } else {
                    primaryButton("Enable Five Prayer Reminders", isBusy: isRequestingReminders) {
                        Task { await enableReminders() }
                    }
                }
                secondaryButton("Not Now") { complete() }
            }
        }
    }

    private func primaryButton(_ title: LocalizedStringKey, isBusy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                } else {
                    Text(title)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(palette.heroStart)
        .frame(minHeight: 52)
        .disabled(isBusy)
    }

    private func secondaryButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(minHeight: 52)
    }

    private func requestCurrentLocation() {
        isRequestingLocation = true
        locationError = nil
        Task {
            do {
                apply(try await container.locationProvider.requestCurrentLocation())
            } catch {
                locationError = error.localizedDescription
            }
            isRequestingLocation = false
        }
    }

    private func enableReminders() async {
        isRequestingReminders = true
        let status = await container.notificationScheduler.requestAuthorization()
        notificationStatus = status
        isRequestingReminders = false
        guard status == .authorized else { return }
        for event in Self.reminderEvents {
            var preference = container.settings.reminder(for: event)
            preference.enabled = true
            container.settings.setReminder(preference, for: event)
        }
        await ReminderCoordinator.reconcile(container: container)
        complete()
    }

    private func apply(_ location: PrayerLocation) {
        container.settings.location = location
        container.settings.locationEducationSeen = true
        container.router.selectedDay = LocalDay(.now, timeZone: location.timeZone)
        locationError = nil
        withAnimation { page = 2 }
    }

    private func complete() {
        container.router.showToday(timeZone: container.settings.location.timeZone)
        container.settings.onboardingComplete = true
    }

    // MARK: - Preview data

    private var previewIdentity: String {
        PrayerTimesQuery(
            day: LocalDay(.now, timeZone: container.settings.location.timeZone),
            location: container.settings.location,
            settings: container.settings.calculation
        ).cacheKey
    }

    private func loadPreview() async {
        let location = container.settings.location
        let calculation = container.settings.calculation
        let day = LocalDay(.now, timeZone: location.timeZone)
        camera = .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
            latitudinalMeters: 4_000,
            longitudinalMeters: 4_000
        ))
        completedCount = ((try? container.trackingRepository.completedPrayerTypes(on: day)) ?? []).count

        let current = try? await container.prayerTimesRepository.day(
            for: PrayerTimesQuery(day: day, location: location, settings: calculation),
            location: location,
            policy: .cacheFirst
        )
        let tomorrow = try? await container.prayerTimesRepository.day(
            for: PrayerTimesQuery(day: day.adding(days: 1, in: location.timeZone), location: location, settings: calculation),
            location: location,
            policy: .cacheFirst
        )
        today = current?.value
        let windows = (current?.value.windows ?? []) + (tomorrow?.value.windows ?? [])
        nextWindow = windows.filter { $0.start > .now }.min { $0.start < $1.start }
    }

    private func refreshNotificationStatus() async {
        notificationStatus = await container.notificationScheduler.authorizationStatus()
    }

    private var nextPrayerTitle: String {
        nextWindow?.prayer.title ?? L10n.string("Prayer times")
    }

    private var trackedTitle: String {
        String(format: L10n.string("%lld of 5"), Int64(completedCount))
    }

    private var qiblaTitle: String {
        let bearing = QiblaGeometry.bearing(from: container.settings.location)
        return "\(Int(bearing.rounded()).formatted(.number.locale(L10n.locale)))°"
    }

    private func time(_ date: Date) -> String {
        PrayerDateFormatting.time(
            date,
            preference: container.settings.calculation.timeFormat,
            timeZone: container.settings.location.timeZone
        )
    }
}

// MARK: - Components

private struct OnboardingPreviewRow<Icon: View, Detail: View>: View {
    let caption: String
    let value: String
    @ViewBuilder let icon: Icon
    @ViewBuilder let detail: Detail

    var body: some View {
        SalahCard {
            HStack(spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.bold())
                    detail
                        .font(.headline)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension OnboardingPreviewRow where Detail == EmptyView {
    init(caption: String, value: String, @ViewBuilder icon: () -> Icon) {
        self.init(caption: caption, value: value, icon: icon, detail: { EmptyView() })
    }
}

private struct OnboardingReminderRow: View {
    let event: PrayerEvent
    let time: String?
    @Environment(\.salahPalette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            TrackerSymbolIcon(symbol: event.symbol, tone: event.iconTone)
            Text(event.title)
                .font(.headline)
            Spacer(minLength: 8)
            Text(time ?? "—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Image(systemName: "bell")
                .font(.subheadline)
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingPageIndicator: View {
    let count: Int
    let current: Int
    @Environment(\.salahPalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? palette.accent : Color.secondary.opacity(0.28))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}
