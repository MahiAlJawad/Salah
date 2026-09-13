import SwiftUI

@MainActor
enum ReminderCoordinator {
    static func reconcile(container: AppContainer) async {
        guard await container.notificationScheduler.authorizationStatus() == .authorized else { return }
        let location = container.settings.location
        let settings = container.settings.calculation
        let today = LocalDay(.now, timeZone: location.timeZone)
        var days: [PrayerDay] = []
        if let current = try? await container.prayerTimesRepository.month(
            containing: today,
            location: location,
            settings: settings,
            policy: .cacheFirst
        ) {
            days.append(contentsOf: current.map(\.value))
        }
        let nextMonthDate = Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: today.date(in: location.timeZone) ?? .now) ?? .now
        let nextMonth = LocalDay(nextMonthDate, timeZone: location.timeZone)
        if let next = try? await container.prayerTimesRepository.month(
            containing: nextMonth,
            location: location,
            settings: settings,
            policy: .cacheFirst
        ) {
            days.append(contentsOf: next.map(\.value))
        }
        await container.notificationScheduler.reconcile(days: days, preferences: container.settings.reminders)
        if container.settings.charityReminder.enabled {
            await container.notificationScheduler.scheduleCharityReminder(container.settings.charityReminder)
        } else {
            await container.notificationScheduler.cancelCharityReminder()
        }
    }
}

struct ReminderEducationSheet: View {
    private enum Target {
        case prayer(PrayerEvent)
        case charity

        var title: String {
            switch self {
            case .prayer(let event): event.title
            case .charity: L10n.string("Charity")
            }
        }
    }

    private let target: Target
    @Bindable var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.salahPalette) private var palette
    @Environment(\.settingsOpener) private var settingsOpener
    @State private var status: NotificationAuthorization = .notDetermined

    init(event: PrayerEvent, container: AppContainer) {
        target = .prayer(event)
        self.container = container
    }

    init(charity container: AppContainer) {
        target = .charity
        self.container = container
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.screenBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Capsule(style: .continuous)
                        .fill(.secondary.opacity(0.18))
                        .frame(width: 36, height: 4)
                        .padding(.top, 8)

                    VStack(spacing: 10) {
                        Text("Reminder permission")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: "bell")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(palette.warm)
                            .accessibilityHidden(true)
                        Text("Enable \(target.title) reminder?")
                            .font(.title3.bold())
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 22)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                    VStack(spacing: 12) {
                        Text("Notifications are optional and scheduled locally on your device.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if status == .denied {
                            Text("Notifications are turned off for this app. Turn them on in Settings to get this reminder.")
                                .font(.body)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)

                    Divider()

                    VStack {
                        if status == .denied {
                            Button {
                                openAppSettings()
                            } label: {
                                Text("Open settings")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(palette.heroStart)
                            .frame(minHeight: 52)
                        } else {
                            Button {
                                Task {
                                    await enableNotifications()
                                }
                            } label: {
                                Text("Enable notifications")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(palette.heroStart)
                            .frame(minHeight: 52)
                        }

                        Divider()

                        Button {
                            dismiss()
                        } label: {
                            Text("Not now")
                                .frame(maxWidth: .infinity)
                        }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(.secondary)
                            .frame(minHeight: 52)
                    }
                    .padding(.horizontal, 10)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(palette.screenBackground)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task { await refreshStatus() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await refreshStatus() }
                }
            }
        }
    }

    private func refreshStatus() async {
        status = await container.notificationScheduler.authorizationStatus()
    }

    private func openAppSettings() {
        settingsOpener()
    }

    private func enableNotifications() async {
        let newStatus = await container.notificationScheduler.requestAuthorization()
        status = newStatus
        if newStatus == .authorized {
            switch target {
            case .prayer(let event):
                var preference = container.settings.reminder(for: event)
                preference.enabled = true
                container.settings.setReminder(preference, for: event)
            case .charity:
                var preference = container.settings.charityReminder
                if preference.date <= .now {
                    preference.date = CharityReminderPreference.suggestedDate()
                }
                preference.enabled = true
                container.settings.charityReminder = preference
            }
            await ReminderCoordinator.reconcile(container: container)
            dismiss()
        }
    }
}

struct RemindersView: View {
    @Bindable var container: AppContainer
    @State private var status: NotificationAuthorization = .notDetermined
    @State private var educationEvent: PrayerEvent = .fajr
    @State private var editingReminderEvent: PrayerEvent?
    @State private var showingEducation = false
    @State private var showingCharityEducation = false
    @State private var charityReminderEnabled: Bool
    @State private var charityReminderDate: Date
    @State private var charityReminderRepeat: CharityReminderRepeat
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.settingsOpener) private var settingsOpener
    @Environment(\.colorScheme) private var colorScheme

    init(container: AppContainer) {
        self.container = container
        _charityReminderEnabled = State(initialValue: container.settings.charityReminder.enabled)
        _charityReminderDate = State(initialValue: container.settings.charityReminder.date)
        _charityReminderRepeat = State(initialValue: container.settings.charityReminder.repeatCycle)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Permission", value: permissionText)
                if status == .denied {
                    Button("Open settings") { openAppSettings() }
                }
            } footer: {
                Text("Notification permission is managed in iPhone Settings.")
            }

            Section {
                charityReminderControls
            } header: {
                Text("Charity")
            } footer: {
                Text("Choose when to begin and whether to remind once, weekly, or monthly. Notifications stay on this device and do not make a donation.")
            }

            Section("Daily Prayers") {
                ForEach(PrayerEvent.allCases.filter { ![.sahri, .iftar].contains($0) }) { event in
                    reminderControls(event)
                }
            }

            Section("Fasting") {
                reminderControls(.sahri)
                reminderControls(.iftar)
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
        .navigationDestination(item: $editingReminderEvent) { event in
            PrayerReminderSettingsView(container: container, event: event)
        }
        .task {
            syncCharityPreference()
            await refreshStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshStatus() }
            }
        }
        .sheet(isPresented: $showingEducation) {
            ReminderEducationSheet(event: educationEvent, container: container)
                .presentationDetents([.medium])
                .onDisappear { Task { await refreshStatus() } }
        }
        .sheet(isPresented: $showingCharityEducation) {
            ReminderEducationSheet(charity: container)
                .presentationDetents([.medium])
                .onDisappear {
                    syncCharityPreference()
                    Task { await refreshStatus() }
                }
        }
    }

    @ViewBuilder
    private var charityReminderControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !charityReminderEnabled, status != .authorized {
                Button {
                    showingCharityEducation = true
                } label: {
                    HStack {
                        Label("Charity reminder", systemImage: "heart.fill")
                        Spacer()
                        Image(systemName: "circle").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("Charity reminder, off")
                .accessibilityHint("Opens reminder settings and permission options")
            } else {
                Toggle(isOn: $charityReminderEnabled) {
                    Label("Charity reminder", systemImage: "heart.fill")
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("charity.reminder.toggle")
                .onChange(of: charityReminderEnabled) { _, enabled in
                    persistCharityEnabled(enabled)
                }
            }

            if charityReminderEnabled {
                Picker("Repeat", selection: $charityReminderRepeat) {
                    ForEach(CharityReminderRepeat.allCases) { repeatCycle in
                        Text(repeatCycle.title).tag(repeatCycle)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("charity.reminder.repeat")
                .onChange(of: charityReminderRepeat) { _, repeatCycle in
                    persistCharityRepeat(repeatCycle)
                }

                charityDatePicker

                LabeledContent("Schedule", value: charityScheduleSummary)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var charityDatePicker: some View {
        if charityReminderRepeat == .once {
            DatePicker(
                "Reminder date",
                selection: $charityReminderDate,
                in: Date.now...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("charity.reminder.date")
            .onChange(of: charityReminderDate) { _, date in
                persistCharityDate(date)
            }
        } else {
            DatePicker(
                "First reminder",
                selection: $charityReminderDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .accessibilityIdentifier("charity.reminder.date")
            .onChange(of: charityReminderDate) { _, date in
                persistCharityDate(date)
            }
        }
    }

    @ViewBuilder
    private func reminderControls(_ event: PrayerEvent) -> some View {
        let preference = container.settings.reminder(for: event)
        VStack(alignment: .leading, spacing: 8) {
            if !preference.enabled, status != .authorized {
                Button {
                    educationEvent = event
                    showingEducation = true
                } label: {
                    HStack {
                        prayerEventLabel(event)
                        Spacer()
                        Image(systemName: "circle").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityLabel("\(event.title) reminder, off")
                .accessibilityHint("Opens reminder settings and permission options")
            } else {
                HStack(spacing: 12) {
                    Button {
                        if preference.enabled {
                            editingReminderEvent = event
                        } else {
                            updateEnabled(true, event: event, opensDetail: true)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            prayerEventLabel(event)
                            Spacer()
                            if preference.enabled {
                                Text(reminderSummary(for: preference))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preference.enabled ? "\(event.title) reminder, \(reminderSummary(for: preference))" : "\(event.title) reminder, off")
                    .accessibilityHint(L10n.dynamic(preference.enabled ? "Opens reminder timing settings" : "Turns on this reminder and opens timing settings"))

                    Toggle(isOn: Binding(
                        get: { container.settings.reminder(for: event).enabled },
                        set: { newValue in updateEnabled(newValue, event: event, opensDetail: newValue) }
                    )) {
                        Text(event.title)
                    }
                    .labelsHidden()
                    .accessibilityLabel(event.title)
                    .accessibilityHint(L10n.dynamic(preference.enabled ? "Turns off and cancels scheduled reminders" : "Turns on this reminder"))
                }
                .frame(minHeight: 44)
            }
        }
    }

    private func prayerEventLabel(_ event: PrayerEvent) -> some View {
        Label {
            Text(event.title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: event.symbol)
                .foregroundStyle(event.iconTone.color(for: colorScheme))
        }
    }

    private func updateEnabled(_ enabled: Bool, event: PrayerEvent, opensDetail: Bool = false) {
        if enabled {
            if status == .authorized {
                var preference = container.settings.reminder(for: event)
                preference.enabled = true
                container.settings.setReminder(preference, for: event)
                Task { await ReminderCoordinator.reconcile(container: container) }
                if opensDetail {
                    editingReminderEvent = event
                }
            }
        } else {
            var preference = container.settings.reminder(for: event)
            preference.enabled = false
            container.settings.setReminder(preference, for: event)
            Task { await container.notificationScheduler.cancel(event: event) }
        }
    }

    private func persistCharityEnabled(_ enabled: Bool) {
        var preference = container.settings.charityReminder
        preference.enabled = enabled
        if enabled, preference.date <= .now {
            preference.date = CharityReminderPreference.suggestedDate()
        }
        charityReminderDate = preference.date
        container.settings.charityReminder = preference
        Task {
            if enabled {
                await container.notificationScheduler.scheduleCharityReminder(preference)
            } else {
                await container.notificationScheduler.cancelCharityReminder()
            }
        }
    }

    private func persistCharityDate(_ date: Date) {
        var preference = container.settings.charityReminder
        preference.date = date
        container.settings.charityReminder = preference
        if preference.enabled {
            Task { await container.notificationScheduler.scheduleCharityReminder(preference) }
        }
    }

    private func persistCharityRepeat(_ repeatCycle: CharityReminderRepeat) {
        var preference = container.settings.charityReminder
        preference.repeatCycle = repeatCycle
        if repeatCycle == .once, preference.date <= .now {
            preference.date = CharityReminderPreference.suggestedDate()
            charityReminderDate = preference.date
        }
        container.settings.charityReminder = preference
        if preference.enabled {
            Task { await container.notificationScheduler.scheduleCharityReminder(preference) }
        }
    }

    private func syncCharityPreference() {
        let preference = container.settings.charityReminder
        charityReminderEnabled = preference.enabled
        charityReminderDate = preference.date
        charityReminderRepeat = preference.repeatCycle
    }

    private var charityScheduleSummary: String {
        switch charityReminderRepeat {
        case .once:
            charityReminderDate.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(L10n.locale))
        case .weekly:
            String(
                format: L10n.string("Every %@ at %@"),
                charityReminderDate.formatted(.dateTime.weekday(.wide).locale(L10n.locale)),
                charityReminderDate.formatted(.dateTime.hour().minute().locale(L10n.locale))
            )
        case .monthly:
            String(
                format: L10n.string("Monthly on day %lld at %@"),
                Int64(Calendar.current.component(.day, from: charityReminderDate)),
                charityReminderDate.formatted(.dateTime.hour().minute().locale(L10n.locale))
            )
        }
    }

    private var permissionText: String {
        switch status {
        case .notDetermined: L10n.string("Not requested")
        case .authorized: L10n.string("Allowed")
        case .denied: L10n.string("Denied")
        }
    }

    private func reminderSummary(for preference: ReminderPreference) -> String {
        preference.offsetMinutes == 0
            ? L10n.string("Exact time")
            : L10n.string("\(preference.offsetMinutes) min before")
    }

    private func refreshStatus() async {
        status = await container.notificationScheduler.authorizationStatus()
    }

    private func openAppSettings() {
        settingsOpener()
    }
}
