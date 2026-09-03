import Observation
import SwiftUI

@MainActor
@Observable
final class TrackerViewModel {
    private let repository: any PrayerTrackingRepository
    private let prayerTimesRepository: any PrayerTimesRepository
    private let settings: AppSettings

    var selectedDay: LocalDay
    var completed: Set<PrayerType> = []
    var lastChanged: PrayerType?
    var errorMessage: String?
    var todayPrayerDay: PrayerDay?

    init(container: AppContainer) {
        repository = container.trackingRepository
        prayerTimesRepository = container.prayerTimesRepository
        settings = container.settings
        selectedDay = LocalDay(.now, timeZone: settings.location.timeZone)
        refresh()
    }

    var completedCount: Int { completed.count }
    var progress: Double { Double(completed.count) / Double(PrayerType.allCases.count) }

    var isMidnightToFajrWindow: Bool {
        guard let todayPrayerDay else { return false }
        return PrayerTimeline.isMidnightToFajrWindow(now: .now, today: todayPrayerDay)
    }

    /// Loads the tracked day's schedule so `isMidnightToFajrWindow` can locate Fajr.
    /// Fails open: without a schedule the tracker stays usable.
    func loadPrayerDay() async {
        let location = settings.location
        let query = PrayerTimesQuery(day: selectedDay, location: location, settings: settings.calculation)
        todayPrayerDay = (try? await prayerTimesRepository.day(for: query, location: location, policy: .cacheFirst))?.value
    }

    func refresh() {
        do {
            completed = try repository.completedPrayerTypes(on: selectedDay)
            errorMessage = nil
        } catch {
            errorMessage = "Tracker data could not be loaded."
        }
    }

    func toggle(_ prayer: PrayerType) {
        let value = !completed.contains(prayer)
        do {
            try repository.setCompleted(value, prayer: prayer, day: selectedDay, timeZone: settings.location.timeZone, source: "tracker")
            if value { completed.insert(prayer) } else { completed.remove(prayer) }
            WidgetDataPublisher.updateCompletion(
                prayer: prayer,
                day: selectedDay,
                completed: value
            )
            lastChanged = prayer
            errorMessage = nil
        } catch {
            errorMessage = "Your change could not be saved."
        }
    }

    func undo() {
        guard let lastChanged else { return }
        toggle(lastChanged)
        self.lastChanged = nil
    }

    func syncDayToNow() {
        let today = LocalDay(.now, timeZone: settings.location.timeZone)
        guard selectedDay != today else { return }
        selectedDay = today
        refresh()
    }
}

private enum TrackerSection: String, CaseIterable, Identifiable {
    case prayers, tasbih, deeds, charity

    var id: Self { self }

    var title: String {
        switch self {
        case .prayers: L10n.string("Salah")
        case .tasbih: L10n.string("Tasbih")
        case .deeds: L10n.string("Nafl")
        case .charity: L10n.string("Charity")
        }
    }
}

struct TrackerView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var viewModel: TrackerViewModel
    @State private var selection = TrackerSection.prayers
    @AppStorage("salah.deeds.istighfar-count") private var tasbihCount = 0
    @AppStorage("salah.deeds.tasbih-goal") private var tasbihGoal = 0
    @AppStorage("salah.deeds.tasbih-day") private var tasbihDay = ""
    @AppStorage(TasbihHistoryLedger.storageKey) private var tasbihHistoryData = Data()
    @AppStorage("salah.deeds.good-deeds-mask") private var goodDeedsMask = 0
    @AppStorage("salah.deeds.good-deeds-day") private var goodDeedsDay = ""
    @AppStorage(NaflHistoryLedger.storageKey) private var naflHistoryData = Data()
    @AppStorage("salah.deeds.charity-total") private var charityTotal = 0
    @AppStorage("salah.deeds.charity-goal") private var charityGoal = 100
    @AppStorage("salah.deeds.charity-month") private var charityMonth = ""
    @AppStorage(CharityLedger.storageKey) private var charityEntriesData = Data()
    @State private var showingAddCharity = false
    @State private var showingCharityGoal = false
    @State private var showingFutureSalahAlert = false

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(initialValue: TrackerViewModel(container: container))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Tracker")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 14)

            trackerSectionPicker
                .padding(.horizontal)

            if selection == .tasbih {
                tasbihTracker
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        switch selection {
                        case .prayers: prayerTracker
                        case .tasbih: EmptyView()
                        case .deeds: goodDeedsTracker
                        case .charity: charityTracker
                        }
                    }
                    .padding()
                }
            }
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Tracker")
        .toolbar(.hidden, for: .navigationBar)
        .alert("Future Salah is not trackable", isPresented: $showingFutureSalahAlert) {
            Button("OK", role: .cancel) { }
        }
        .task {
            prepareLocalTrackers()
        }
        .onAppear { viewModel.refresh() }
        .task(id: PrayerTimesQuery(
            day: viewModel.selectedDay,
            location: container.settings.location,
            settings: container.settings.calculation
        ).cacheKey) {
            await viewModel.loadPrayerDay()
        }
        .task {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    InsightsView(container: container)
                } label: {
                    Label("Insights", systemImage: "chart.bar.xaxis")
                }
                .accessibilityIdentifier("tracker.insights")
            }
        }
        .task {
            prepareLocalTrackers()
        }
        .task {
            while !Task.isCancelled {
                viewModel.syncDayToNow()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private var trackerSectionPicker: some View {
        Picker("Tracker section", selection: $selection) {
            ForEach(TrackerSection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Tracker section")
    }

    @ViewBuilder
    private var prayerTracker: some View {
        SalahCard(isTransparent: true) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isToday ? L10n.string("Today’s Salah") : PrayerDateFormatting.fullDate(viewModel.selectedDay, timeZone: container.settings.location.timeZone))
                        .font(.title3.bold())
                    Text("Private and stored on this device")
                        .font(.caption).foregroundStyle(.white.opacity(0.82))
                }
                Spacer()
                Text("\(viewModel.completedCount)/5")
                    .font(.largeTitle.bold().monospacedDigit())
            }
            ProgressView(value: viewModel.progress)
                .tint(.white)
                .accessibilityLabel("Daily completion")
                .accessibilityValue("\(viewModel.completedCount) of 5 prayers completed")
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [palette.heroStart, palette.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )

        if let message = viewModel.errorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.red)
        }

        VStack(spacing: 10) {
            ForEach(PrayerType.allCases) { prayer in
                TrackerPrayerRow(prayer: prayer, completed: viewModel.completed.contains(prayer)) {
                    if viewModel.isMidnightToFajrWindow {
                        showingFutureSalahAlert = true
                    } else {
                        withAnimation(.snappy) { viewModel.toggle(prayer) }
                    }
                }
            }
        }
    }

    private var tasbihTracker: some View {
        TasbihCounterPad(count: $tasbihCount, goal: $tasbihGoal) {
            tasbihHistoryData = TasbihHistoryLedger.incrementing(goal: tasbihGoal, on: today, in: tasbihHistoryData)
        }
    }

    @ViewBuilder
    private var goodDeedsTracker: some View {
        HStack {
            Text("Nafl today").font(.title3.bold())
            Spacer()
            Text("\(goodDeedsCount) of \(NaflPractice.allCases.count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }

        VStack(spacing: 12) {
            ForEach(NaflPractice.allCases) { deed in
                SalahCard {
                    GoodDeedRow(
                        title: deed.title,
                        symbol: deed.symbol,
                        completed: isGoodDeedCompleted(deed.id),
                        accent: palette.accent
                    ) {
                        withAnimation(.snappy) {
                            toggleGoodDeed(deed.id)
                        }
                    }
                }
            }
        }

        Text("These reflections stay on this device and reset only when you choose to change them.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var charityTracker: some View {
        SalahCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Given this month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(monthlyCharityTotal, format: .currency(code: charityCurrencyCode))
                        .font(.largeTitle.bold().monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Monthly intention")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(charityGoal, format: .currency(code: charityCurrencyCode))
                        .font(.headline.monospacedDigit())
                }
            }

            ProgressView(value: min(monthlyCharityTotal, Double(charityGoal)), total: Double(max(1, charityGoal)))
                .accessibilityLabel("Monthly charity intention")
                .accessibilityValue("\(monthlyCharityTotal.formatted(.currency(code: charityCurrencyCode).locale(L10n.locale))) of \(charityGoal.formatted(.currency(code: charityCurrencyCode).locale(L10n.locale)))")

            HStack {
                Label("\(monthlyCharityEntries.count) gifts", systemImage: "heart.circle.fill")
                Spacer()
                Text(charityProgress, format: .percent.precision(.fractionLength(0)))
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button("Add Giving", systemImage: "plus") { showingAddCharity = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("charity.add-giving")

            Button("Edit Monthly Intention", systemImage: "target") { showingCharityGoal = true }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }

        SalahCard {
            NavigationLink {
                RemindersView(container: container)
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Charity Reminder")
                        Text(charityReminderSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(palette.accent)
                }
            }
            .accessibilityHint("Opens the Charity section in Reminders")
            .accessibilityIdentifier("charity.reminder.link")
        }

        if !monthlyCategoryTotals.isEmpty {
            SalahCard {
                Text("This Month by Purpose").font(.headline)
                ForEach(monthlyCategoryTotals, id: \.category) { item in
                    HStack {
                        Label(item.category.title, systemImage: item.category.symbol)
                        Spacer()
                        Text(item.total, format: .currency(code: charityCurrencyCode))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                }
            }
        }

        SalahCard {
            HStack {
                Text("Recent Giving").font(.headline)
                Spacer()
                NavigationLink("View All") {
                    CharityHistoryView(container: container)
                }
                .font(.subheadline)
            }

            if charityEntries.isEmpty {
                Text("No giving recorded yet. Add an entry when you give to build a private history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(charityEntries.prefix(3)) { entry in
                    CharityEntryRow(entry: entry)
                }
            }

            Text("Salah records your reflection only. It never collects or processes donations.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showingAddCharity) {
            AddCharityEntryView(currencyCode: charityCurrencyCode) { entry in
                addCharityEntry(entry)
            }
        }
        .sheet(isPresented: $showingCharityGoal) {
            CharityGoalEditor(goal: charityGoal, currencyCode: charityCurrencyCode) {
                charityGoal = $0
            }
        }
    }

    private var today: LocalDay {
        LocalDay(.now, timeZone: container.settings.location.timeZone)
    }

    private var goodDeedsCount: Int {
        NaflPractice.allCases.filter { goodDeedsMask & (1 << $0.id) != 0 }.count
    }

    private func isGoodDeedCompleted(_ id: Int) -> Bool {
        goodDeedsMask & (1 << id) != 0
    }

    private func toggleGoodDeed(_ id: Int) {
        if goodDeedsMask & (1 << id) != 0 {
            goodDeedsMask &= ~(1 << id)
        } else {
            goodDeedsMask |= (1 << id)
        }
        naflHistoryData = NaflHistoryLedger.recording(mask: goodDeedsMask, on: today, in: naflHistoryData)
    }

    private func prepareLocalTrackers() {
        if tasbihDay.isEmpty {
            tasbihDay = today.key
            if tasbihCount > 0, !TasbihHistoryLedger.decode(tasbihHistoryData).contains(where: { $0.day == today }) {
                tasbihHistoryData = TasbihHistoryLedger.recording(count: tasbihCount, goal: tasbihGoal, on: today, in: tasbihHistoryData)
            }
        } else if tasbihDay != today.key {
            if let priorDay = LocalDay(stableKey: tasbihDay),
               tasbihCount > 0,
               !TasbihHistoryLedger.decode(tasbihHistoryData).contains(where: { $0.day == priorDay }) {
                tasbihHistoryData = TasbihHistoryLedger.recording(count: tasbihCount, goal: tasbihGoal, on: priorDay, in: tasbihHistoryData)
            }
            tasbihDay = today.key
            tasbihCount = 0
        }

        if goodDeedsDay != today.key {
            if let priorDay = LocalDay(stableKey: goodDeedsDay), goodDeedsMask > 0 {
                naflHistoryData = NaflHistoryLedger.recording(mask: goodDeedsMask, on: priorDay, in: naflHistoryData)
            }
            goodDeedsDay = today.key
            goodDeedsMask = 0
            naflHistoryData = NaflHistoryLedger.recording(mask: 0, on: today, in: naflHistoryData)
        } else if !NaflHistoryLedger.decode(naflHistoryData).contains(where: { $0.day == today }) {
            naflHistoryData = NaflHistoryLedger.recording(mask: goodDeedsMask, on: today, in: naflHistoryData)
        }
        let month = String(format: "%04d-%02d", today.year, today.month)
        var entries = charityEntries
        if CharityLedger.needsCurrencyMigration(charityEntriesData) {
            charityEntriesData = CharityLedger.encode(entries)
        }
        if entries.isEmpty, charityMonth == month, charityTotal > 0 {
            entries = [
                CharityEntry(
                    amount: Double(charityTotal),
                    date: .now,
                    category: .other,
                    note: L10n.string("Imported monthly total")
                )
            ]
            charityEntriesData = CharityLedger.encode(entries)
        }
        charityMonth = month
        charityTotal = Int(
            CharityLedger.total(
                entries.filter { $0.currencyCode == charityCurrencyCode },
                inMonthContaining: .now
            ).rounded()
        )
    }

    private var charityCurrencyCode: String {
        CharityCurrency.code()
    }

    private var charityEntries: [CharityEntry] {
        CharityLedger.decode(charityEntriesData).sorted { $0.date > $1.date }
    }

    private var monthlyCharityEntries: [CharityEntry] {
        CharityLedger.entries(charityEntries, inMonthContaining: .now)
            .filter { $0.currencyCode == charityCurrencyCode }
    }

    private var monthlyCharityTotal: Double {
        monthlyCharityEntries.reduce(0) { $0 + $1.amount }
    }

    private var charityProgress: Double {
        guard charityGoal > 0 else { return 0 }
        return min(1, monthlyCharityTotal / Double(charityGoal))
    }

    private var monthlyCategoryTotals: [(category: CharityCategory, total: Double)] {
        Dictionary(grouping: monthlyCharityEntries, by: \.category)
            .map { (category: $0.key, total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
    }

    private var charityReminderSummary: String {
        let preference = container.settings.charityReminder
        guard preference.enabled,
              let nextDate = CharityReminderPlan.make(preference: preference, now: .now, limit: 1).first else {
            return L10n.string("Choose a date and time")
        }
        return "\(preference.repeatCycle.title) • \(nextDate.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().locale(L10n.locale)))"
    }

    private func addCharityEntry(_ entry: CharityEntry) {
        var entries = charityEntries
        entries.append(entry)
        charityEntriesData = CharityLedger.encode(entries)
        charityTotal = Int(
            CharityLedger.total(
                entries.filter { $0.currencyCode == charityCurrencyCode },
                inMonthContaining: .now
            ).rounded()
        )
    }

    private var isToday: Bool {
        viewModel.selectedDay == LocalDay(.now, timeZone: container.settings.location.timeZone)
    }
}
