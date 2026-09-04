import SwiftUI

struct CurrentPrayerCard: View {
    let moment: PrayerCardMoment
    @Environment(\.salahPalette) private var palette

    var body: some View {
        let displayed = moment.event
        let countdown = moment.remaining
        SalahCard(isTransparent: true) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.22), lineWidth: 7)
                    Circle()
                        .trim(from: 0, to: moment.progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: displayed?.symbol ?? "clock.fill")
                        .font(.title2)
                }
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(cardHeading(for: displayed))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(displayed?.title ?? L10n.string("Schedule complete"))
                        .font(.title.bold())
                    if let remaining = countdown {
                        Text(PrayerDateFormatting.countdown(remaining))
                            .font(.title2.bold().monospacedDigit())
                        Text(countdownCaption(for: displayed))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
            }
            .foregroundStyle(.white)
        }
        .background(
            palette.heroGradient,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .shadow(color: palette.heroEnd.opacity(0.28), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }

    private func cardHeading(for event: PrayerCardEvent?) -> String {
        guard let event else { return L10n.string("Current prayer") }
        if moment.isCurrent {
            return event.isNafl ? L10n.string("Current nafl prayer") : L10n.string("Current prayer")
        }
        return event.isNafl
            ? L10n.string("Next nafl prayer · \(event.title)")
            : L10n.string("Next prayer · \(event.title)")
    }

    private func countdownCaption(for event: PrayerCardEvent?) -> String {
        guard let event else { return L10n.string("Waqt ends in") }
        if moment.isCurrent {
            return event.isNafl ? L10n.string("Nafl time ends in") : L10n.string("Waqt ends in")
        }
        return L10n.string("until \(event.title) begins")
    }
}

struct PrayerScheduleRow: View {
    let window: PrayerWindow
    let day: PrayerDay
    let preference: TimeFormatPreference
    let isActive: Bool
    let isCompleted: Bool
    var showsDisclosure = true
    private let trailingContent: (() -> AnyView)?
    @Environment(\.salahPalette) private var palette

    init(
        window: PrayerWindow,
        day: PrayerDay,
        preference: TimeFormatPreference,
        isActive: Bool,
        isCompleted: Bool,
        showsDisclosure: Bool = true
    ) {
        self.window = window
        self.day = day
        self.preference = preference
        self.isActive = isActive
        self.isCompleted = isCompleted
        self.showsDisclosure = showsDisclosure
        trailingContent = nil
    }

    init<Trailing: View>(
        window: PrayerWindow,
        day: PrayerDay,
        preference: TimeFormatPreference,
        isActive: Bool,
        showsDisclosure: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.window = window
        self.day = day
        self.preference = preference
        self.isActive = isActive
        isCompleted = false
        self.showsDisclosure = showsDisclosure
        trailingContent = { AnyView(trailing()) }
    }

    var body: some View {
        HStack(spacing: 10) {
            PrayerIcon(prayer: window.prayer, active: isActive)

            VStack(alignment: .leading, spacing: 4) {
                Text(window.prayer.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isActive { currentBadge }
            }

            Spacer(minLength: 6)

            Text("\(PrayerDateFormatting.time(window.start, preference: preference, timeZone: day.timeZone)) - \(PrayerDateFormatting.time(window.displayEnd, preference: preference, timeZone: day.timeZone))")
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .layoutPriority(1)

            if showsDisclosure {
                if isCompleted { completionImage }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            } else if let trailingContent {
                trailingContent()
            } else {
                completionImage
            }
        }
        .padding(.horizontal)
        .frame(minHeight: 64)
        .background(isActive ? palette.accentSoft : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: trailingContent == nil ? .combine : .contain)
        .accessibilityLabel("\(window.prayer.title), starts \(PrayerDateFormatting.time(window.start, preference: preference, timeZone: day.timeZone)), ends \(PrayerDateFormatting.time(window.displayEnd, preference: preference, timeZone: day.timeZone))\(isActive ? ", current prayer" : "")\(isCompleted ? ", completed" : "")")
        .accessibilityHint(L10n.dynamic(showsDisclosure ? "Opens prayer details" : (isCompleted ? "Marks this prayer as not completed" : "Marks this prayer as completed")))
    }

    @ViewBuilder
    private var completionImage: some View {
        if isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var currentBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.caption2.weight(.semibold))
            Text("Current")
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption2.weight(.semibold))
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .foregroundStyle(palette.accent)
        .background(palette.accentSoft, in: Capsule())
        .accessibilityLabel("Current prayer")
    }
}

struct PrayerCompletionControl: View {
    let viewModel: TodayViewModel
    let prayer: PrayerType
    let toggle: () -> Void
    @Environment(\.salahPalette) private var palette

    var body: some View {
        let isCompleted = viewModel.completed.contains(prayer)
        Button(action: toggle) {
            Group {
                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(palette.accent)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        // Preserve the original 20-point trailing-icon footprint in the row.
        .padding(.horizontal, -12)
        .accessibilityLabel(isCompleted ? "Completed" : "Not completed")
        .accessibilityHint(L10n.dynamic(isCompleted ? "Marks this prayer as not completed" : "Marks this prayer as completed"))
    }
}

struct PrayerCompletionSummary: View {
    let viewModel: TodayViewModel

    var body: some View {
        Text("\(viewModel.completed.count) of 5 prayed")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct PrayerDetailSheet: View {
    let window: PrayerWindow
    let day: PrayerDay
    @Bindable var container: AppContainer
    let isCompleted: Bool
    let toggleCompletion: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingReminderEducation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PrayerIcon(prayer: window.prayer, active: window.contains(.now))
                        .scaleEffect(1.25)
                        .padding(.top)
                    Text(window.prayer.title).font(.largeTitle.bold())
                    if window.contains(.now) { StatusBadge(text: "Current prayer", symbol: "clock.fill") }

                    HStack(spacing: 12) {
                        detailBox("Starts", window.start)
                        detailBox("Ends", window.displayEnd)
                    }
                    SalahCard {
                        Label("Calculation", systemImage: "function")
                            .font(.headline)
                        Text("\(day.methodName) · \(container.settings.calculation.madhab.title)")
                        Text("Prayer windows may differ from local authorities. Review your calculation settings and confirm locally when needed.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }

                    Button(L10n.dynamic(isCompleted ? "Mark as Not Completed" : "Mark as Completed")) {
                        toggleCompletion()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)

                    Button(L10n.dynamic(container.settings.reminder(for: PrayerEvent(rawValue: window.prayer.rawValue) ?? .fajr).enabled ? "Manage Reminder" : "Enable Reminder")) {
                        showingReminderEducation = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
            .navigationTitle("Prayer Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showingReminderEducation) {
                ReminderEducationSheet(event: PrayerEvent(rawValue: window.prayer.rawValue) ?? .fajr, container: container)
                    .presentationDetents([.medium])
            }
        }
    }

    private func detailBox(_ title: String, _ date: Date) -> some View {
        SalahCard {
            Text(L10n.dynamic(title)).font(.caption).foregroundStyle(.secondary)
            Text(PrayerDateFormatting.time(date, preference: container.settings.calculation.timeFormat, timeZone: day.timeZone))
                .font(.title3.bold().monospacedDigit())
        }
    }
}
