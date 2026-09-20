import Observation
import SwiftUI

@MainActor
@Observable
final class CalendarViewModel {
    private let container: AppContainer
    var selectedDay: LocalDay
    var monthAnchor: LocalDay
    var anchoredToToday = true
    var trackerDays: Set<LocalDay> = []
    var selectedPrayer: PrayerType?
    private var pendingPrayer: PrayerType?
    var prayerDay: PrayerDay?
    private var prayerRequestID = UUID()
    var loadingPrayerTimes = false
    var prayerError = false
    var offlineDate: Date?
    var completed: Set<PrayerType> = []
    var tasbih: TasbihDailyRecord?
    var naflMask = 0
    var giving: [CharityEntry] = []
    var loadError: String?
    var saveError: String?
    var savedDay: LocalDay?
    private var undoNafl: (day: LocalDay, practice: NaflPractice, wasCompleted: Bool)?

    init(container: AppContainer) {
        self.container = container
        let today = container.datedTracker.today(in: container.settings.location.timeZone)
        selectedDay = today
        monthAnchor = LocalDay(year: today.year, month: today.month, day: 1)
    }

    var timeZone: TimeZone { container.settings.location.timeZone }
    var today: LocalDay { container.datedTracker.today(in: timeZone) }
    var canUndo: Bool { undoNafl?.day == selectedDay }
    var dateTitle: String { PrayerDateFormatting.fullDate(selectedDay, timeZone: timeZone) }
    var monthDays: [LocalDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = monthAnchor.date(in: timeZone), let range = calendar.range(of: .day, in: .month, for: date) else { return [] }
        return range.map { LocalDay(year: monthAnchor.year, month: monthAnchor.month, day: $0) }
    }

    func load(policy: CachePolicy = .cacheFirst) async {
        refreshRecords()
        let requestID = UUID()
        prayerRequestID = requestID
        let day = selectedDay
        let location = container.settings.location
        let calculation = container.settings.calculation
        prayerDay = nil
        offlineDate = nil
        prayerError = false
        loadingPrayerTimes = true
        defer { if prayerRequestID == requestID { loadingPrayerTimes = false } }
        do {
            let result = try await container.prayerTimesRepository.day(
                for: PrayerTimesQuery(day: day, location: location, settings: calculation),
                location: location, policy: policy
            )
            guard !Task.isCancelled, prayerRequestID == requestID, selectedDay == day, location == container.settings.location,
                  calculation == container.settings.calculation else { return }
            prayerDay = result.value
            if let pendingPrayer { selectedPrayer = pendingPrayer; self.pendingPrayer = nil }
            offlineDate = result.isStale ? result.value.fetchedAt : nil
        } catch {
            guard !Task.isCancelled, prayerRequestID == requestID, selectedDay == day else { return }
            prayerError = true
        }
    }

    func refreshRecords() {
        do {
            try container.datedTracker.reconcile(in: timeZone)
            let prayers = try container.trackingRepository.allRecords()
            let tasbihRecords = try container.trackerHistoryRepository.tasbihRecords()
            let naflRecords = try container.trackerHistoryRepository.naflRecords()
            let entries = try container.trackerHistoryRepository.charityEntries()
            completed = Set(prayers.filter { $0.localDay == selectedDay && $0.completed }.map(\.prayer))
            tasbih = tasbihRecords.first { $0.day == selectedDay }
            naflMask = naflRecords.first { $0.day == selectedDay }?.completedMask ?? 0
            giving = entries
            trackerDays = Set(prayers.filter(\.completed).map(\.localDay))
                .union(tasbihRecords.filter { $0.count > 0 }.map(\.day))
                .union(naflRecords.filter { $0.completedCount > 0 }.map(\.day))
                .union(entries.map { LocalDay($0.date, timeZone: timeZone) })
            loadError = nil
        } catch {
            loadError = "Tracker data could not be loaded."
        }
    }

    func select(_ day: LocalDay, followsToday: Bool? = nil) {
        guard day <= today else { return }
        anchoredToToday = followsToday ?? (day == today)
        monthAnchor = LocalDay(year: day.year, month: day.month, day: 1)
        guard selectedDay != day else { refreshRecords(); return }
        selectedDay = day
        selectedPrayer = nil
        pendingPrayer = nil
        prayerDay = nil
        completed = []
        tasbih = nil
        naflMask = 0
        giving = []
        undoNafl = nil
        savedDay = nil
        saveError = nil
        refreshRecords()
    }

    func moveMonth(_ amount: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = monthAnchor.date(in: timeZone),
              let moved = calendar.date(byAdding: .month, value: amount, to: date) else { return }
        let local = LocalDay(moved, timeZone: timeZone)
        monthAnchor = LocalDay(year: local.year, month: local.month, day: 1)
    }

    func syncDayToNow() {
        if anchoredToToday, selectedDay != today { select(today, followsToday: true) }
        refreshRecords()
    }

    func navigate(to target: CalendarPrayerTarget) {
        guard target.day <= today else { return }
        select(target.day, followsToday: false)
        if prayerDay != nil { selectedPrayer = target.prayer } else { pendingPrayer = target.prayer }
    }

    func togglePrayer(_ prayer: PrayerType, on targetDay: LocalDay? = nil) {
        let day = targetDay ?? selectedDay
        do {
            try container.datedTracker.requireTrackable(day, in: timeZone)
            if let prayerDay, prayerDay.localDay == day, PrayerTimeline.isMidnightToFajrWindow(now: .now, today: prayerDay) {
                throw DatedTrackingError.futureDay
            }
            let value = try !container.trackingRepository.completedPrayerTypes(on: day).contains(prayer)
            try container.trackingRepository.setCompleted(value, prayer: prayer, day: day, timeZone: timeZone, source: "calendar")
            WidgetDataPublisher.updateCompletion(prayer: prayer, day: day, completed: value)
            container.datedTracker.recordsChanged()
            didSave(on: day)
        } catch { didFail() }
    }

    func toggleNafl(_ practice: NaflPractice) {
        do {
            let mask = try container.trackerHistoryRepository.naflRecord(on: selectedDay)?.completedMask ?? 0
            try container.datedTracker.setNaflMask(mask ^ (1 << practice.rawValue), on: selectedDay, in: timeZone)
            undoNafl = (selectedDay, practice, mask & (1 << practice.rawValue) != 0)
            didSave()
        } catch { didFail() }
    }

    func undo() {
        guard let change = undoNafl, change.day == selectedDay else { return }
        do {
            let current = try container.trackerHistoryRepository.naflRecord(on: change.day)?.completedMask ?? 0
            let bit = 1 << change.practice.rawValue
            let mask = change.wasCompleted ? current | bit : current & ~bit
            try container.datedTracker.setNaflMask(mask, on: change.day, in: timeZone)
            undoNafl = nil
            didSave()
        } catch { didFail() }
    }

    func replaceTasbih(_ count: Int, on day: LocalDay) throws {
        do {
            try container.datedTracker.replaceTasbih(count, on: day, in: timeZone)
            didSave(on: day)
        } catch {
            didFail()
            throw error
        }
    }

    func addGiving(_ entry: CharityEntry) throws {
        do {
            try container.datedTracker.addGiving(entry, in: timeZone)
            didSave(on: LocalDay(entry.date, timeZone: timeZone))
        } catch {
            didFail()
            throw error
        }
    }

    private func didSave(on day: LocalDay? = nil) {
        saveError = nil
        savedDay = day ?? selectedDay
        refreshRecords()
    }

    private func didFail() {
        savedDay = nil
        saveError = "Your change could not be saved."
    }
}

struct PrayerCalendarView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: CalendarViewModel
    @State private var appliedTargetID: UUID?
    @State private var selection = TrackerSection.prayers
    @State private var gridExpanded = true
    @State private var showingFutureSalahAlert = false
    @State private var editingTasbihDay: LocalDay?
    @State private var addingGivingDay: LocalDay?
    @AppStorage(CharityCurrency.storageKey) private var currencyCode = CharityCurrency.code()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(initialValue: CalendarViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                HStack {
                    Text("Calendar").font(.largeTitle.bold())
                    Spacer()
                    Button("Today") { viewModel.select(viewModel.today, followsToday: true) }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("calendar.today")
                }
                monthGrid
                Section {
                    if let error = viewModel.loadError {
                        VStack {
                            Text(L10n.dynamic(error)).foregroundStyle(.red)
                            Button("Retry") { viewModel.refreshRecords() }
                        }
                    } else {
                        categoryContent
                            .disabled(viewModel.selectedDay > viewModel.today)
                    }
                    if let error = viewModel.saveError {
                        Text(L10n.dynamic(error)).font(.footnote).foregroundStyle(.red)
                            .accessibilityIdentifier("calendar.save-error")
                    } else if let day = viewModel.savedDay {
                        HStack {
                            Label(L10n.string("Saved for \(PrayerDateFormatting.fullDate(day, timeZone: viewModel.timeZone))"), systemImage: "checkmark.circle.fill")
                            if selection == .deeds, viewModel.canUndo { Button("Undo") { viewModel.undo() } }
                        }
                        .font(.footnote)
                        .accessibilityIdentifier("calendar.saved")
                    }
                } header: {
                    selectedDateHeader
                        .padding(.vertical, 8)
                        .background(palette.screenBackground)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(palette.screenBackground)
        .alert("Future Salah is not trackable", isPresented: $showingFutureSalahAlert) {
            Button("OK", role: .cancel) { }
        }
        .navigationTitle("Calendar")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await viewModel.load(policy: .reload) }
        .task(id: PrayerTimesQuery(day: viewModel.selectedDay, location: container.settings.location, settings: container.settings.calculation).cacheKey) {
            await viewModel.load()
        }
        .task {
            while !Task.isCancelled {
                viewModel.syncDayToNow()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onAppear {
            viewModel.syncDayToNow()
            applyCalendarTarget(container.router.calendarPrayerTarget)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.syncDayToNow() }
        }
        .onChange(of: container.datedTracker.revision) { _, _ in viewModel.refreshRecords() }
        .onChange(of: container.router.calendarPrayerTarget) { _, target in applyCalendarTarget(target) }
        .sheet(item: $editingTasbihDay) { day in
            TasbihTotalEditor(day: day, timeZone: viewModel.timeZone, count: viewModel.tasbih?.count ?? 0) {
                try viewModel.replaceTasbih($0, on: day)
            }
        }
        .sheet(item: $addingGivingDay) { day in
            AddCharityEntryView(currencyCode: $currencyCode, initialDate: min(day.date(in: viewModel.timeZone) ?? .now, .now), timeZone: viewModel.timeZone) {
                try viewModel.addGiving($0)
            }
        }
        .sheet(item: $viewModel.selectedPrayer) { prayer in
            if let day = viewModel.prayerDay, let window = day.window(for: prayer) {
                PrayerDetailSheet(window: window, day: day, container: container, isCompleted: viewModel.completed.contains(prayer)) {
                    viewModel.togglePrayer(prayer, on: day.localDay)
                }
            }
        }
    }

    private var monthGrid: some View {
        VStack(spacing: 6) {
            HStack {
                Button { viewModel.moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("Previous month")
                Spacer()
                Button { gridExpanded.toggle() } label: {
                    HStack {
                        Text(monthTitle).font(.headline)
                        Image(systemName: gridExpanded ? "chevron.up" : "chevron.down")
                    }.frame(minHeight: 44)
                }
                .accessibilityLabel(L10n.dynamic(gridExpanded ? "Collapse calendar" : "Expand calendar"))
                .accessibilityValue(monthTitle)
                .accessibilityIdentifier("calendar.collapse")
                Spacer()
                Button { viewModel.moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("Next month")
            }
            if gridExpanded {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(Array(localizedShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(0..<leadingBlankCount, id: \.self) { _ in Color.clear.frame(height: 44) }
                    ForEach(viewModel.monthDays) { day in calendarCell(day) }
                }
            }
        }
    }

    private var selectedDateHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Button { viewModel.select(viewModel.selectedDay.adding(days: -1, in: viewModel.timeZone)) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous day")
                .accessibilityIdentifier("calendar.previous-day")
                Spacer(minLength: 0)
                VStack(spacing: 4) {
                    Text(viewModel.dateTitle).font(.headline).multilineTextAlignment(.center)
                        .accessibilityIdentifier("calendar.selected-date")
                    Text(L10n.dynamic(viewModel.selectedDay == viewModel.today ? "Today" : "Past day"))
                        .font(.caption).foregroundStyle(palette.accent)
                }
                Spacer(minLength: 0)
                Button { viewModel.select(viewModel.selectedDay.adding(days: 1, in: viewModel.timeZone)) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(viewModel.selectedDay >= viewModel.today)
                .accessibilityLabel("Next day")
                .accessibilityIdentifier("calendar.next-day")
            }
            TrackerSectionPicker(selection: $selection)
            .accessibilityIdentifier("calendar.categories")
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch selection {
        case .prayers: salahRecords
        case .deeds: naflRecords
        case .tasbih:
            SalahCard {
                Text("Tasbih for this day").font(.title3.bold())
                Text("Recorded total").font(.subheadline).foregroundStyle(.secondary)
                Text(viewModel.tasbih?.count ?? 0, format: .number).font(.largeTitle.bold().monospacedDigit())
                if (viewModel.tasbih?.count ?? 0) == 0 {
                    Text("No dhikr recorded for this day.").font(.footnote).foregroundStyle(.secondary)
                }
                Button("Edit total") { editingTasbihDay = viewModel.selectedDay }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("calendar.edit-tasbih")
            }
        case .charity: charityRecords
        }
    }

    private var salahRecords: some View {
        VStack(spacing: 12) {
            if viewModel.loadingPrayerTimes { ProgressView("Loading prayer times…") }
            if viewModel.prayerError {
                Text("Prayer times could not be loaded. Your records are still available.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Retry prayer times") { Task { await viewModel.load(policy: .reload) } }
            }
            if let date = viewModel.offlineDate { OfflineBanner(lastUpdated: date) }
            VStack(spacing: 0) {
                ForEach(PrayerType.allCases) { prayer in
                    if let day = viewModel.prayerDay, let window = day.window(for: prayer) {
                        Button {
                            if PrayerTimeline.isMidnightToFajrWindow(now: .now, today: day) {
                                showingFutureSalahAlert = true
                            } else { viewModel.selectedPrayer = prayer }
                        } label: {
                            PrayerScheduleRow(window: window, day: day, preference: container.settings.calculation.timeFormat,
                                              isActive: false, isCompleted: viewModel.completed.contains(prayer))
                        }.buttonStyle(.plain)
                    } else {
                        GoodDeedRow(title: prayer.title, symbol: prayer.symbol, tone: prayer.iconTone,
                                    completed: viewModel.completed.contains(prayer), accent: palette.accent) {
                            viewModel.togglePrayer(prayer)
                        }.padding()
                    }
                    if prayer != .isha { Divider().padding(.leading, 62) }
                }
            }
            .background(
                colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : palette.groupedSurface,
                in: RoundedRectangle(cornerRadius: 18)
            )
            Text("\(viewModel.completed.count) of 5 prayers recorded.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var naflRecords: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Nafl").font(.title3.bold())
                Spacer()
                Text("\(NaflPractice.allCases.filter { viewModel.naflMask & (1 << $0.rawValue) != 0 }.count) of 5 recorded")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            SalahCard {
                ForEach(NaflPractice.allCases) { practice in
                    GoodDeedRow(title: practice.title, symbol: practice.symbol, tone: practice.iconTone,
                                completed: viewModel.naflMask & (1 << practice.rawValue) != 0, accent: palette.accent) {
                        viewModel.toggleNafl(practice)
                    }
                    if practice != NaflPractice.allCases.last { Divider() }
                }
            }
        }
    }

    private var charityRecords: some View {
        let daily = CharityLedger.entries(viewModel.giving, on: viewModel.selectedDay, timeZone: viewModel.timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = viewModel.timeZone
        let monthly = CharityLedger.entries(viewModel.giving, inMonthContaining: viewModel.selectedDay.date(in: viewModel.timeZone) ?? .now, calendar: calendar)
        return VStack(spacing: 16) {
            SalahCard {
                Text("Given this day").font(.headline)
                currencyTotals(daily)
                if daily.isEmpty {
                    Text("No giving recorded for this day.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(daily) { entry in CharityEntryRow(entry: entry, timeZone: viewModel.timeZone) }
                Button("Add Giving", systemImage: "plus") { addingGivingDay = viewModel.selectedDay }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("calendar.add-giving")
            }
            SalahCard {
                Text("Selected month total").font(.headline)
                Text(PrayerDateFormatting.fullDate(viewModel.selectedDay, timeZone: viewModel.timeZone))
                    .font(.caption).foregroundStyle(.secondary)
                currencyTotals(monthly)
                if monthly.isEmpty { Text("No giving recorded this month.").foregroundStyle(.secondary) }
            }
            Text("A private record of your giving.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func currencyTotals(_ entries: [CharityEntry]) -> some View {
        ForEach(CharityLedger.totalsByCurrency(entries), id: \.currency) { total in
            Text(total.amount, format: .currency(code: total.currency).locale(L10n.locale))
                .font(.title2.bold().monospacedDigit())
                .accessibilityLabel("\(total.currency) \(total.amount.formatted(.number.locale(L10n.locale)))")
        }
    }

    private func calendarCell(_ day: LocalDay) -> some View {
        let selected = day == viewModel.selectedDay
        let isFuture = day > viewModel.today
        return Button { viewModel.select(day, followsToday: day == viewModel.today) } label: {
            ZStack(alignment: .bottom) {
                Text(day.day, format: .number.grouping(.never))
                    .font(.body.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? .white : (isFuture ? .secondary : .primary))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selected ? palette.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if day == viewModel.today, !selected { RoundedRectangle(cornerRadius: 12).stroke(palette.accent, lineWidth: 2) }
                    }
                    .opacity(isFuture ? 0.4 : 1)
                if viewModel.trackerDays.contains(day), !isFuture {
                    Circle().fill(selected ? .white : palette.accent).frame(width: 5, height: 5).padding(.bottom, 4)
                }
            }
        }
        .disabled(isFuture)
        .accessibilityLabel(PrayerDateFormatting.fullDate(day, timeZone: viewModel.timeZone))
        .accessibilityValue(viewModel.trackerDays.contains(day) ? L10n.string("Has tracker records") : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("calendar.day.\(day.key)")
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.timeZone = viewModel.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return viewModel.monthAnchor.date(in: viewModel.timeZone).map(formatter.string) ?? viewModel.monthAnchor.key
    }

    private var localizedShortWeekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter.shortStandaloneWeekdaySymbols
    }

    private var leadingBlankCount: Int {
        guard let date = viewModel.monthAnchor.date(in: viewModel.timeZone) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = viewModel.timeZone
        return max(0, calendar.component(.weekday, from: date) - 1)
    }

    private func applyCalendarTarget(_ target: CalendarPrayerTarget?) {
        guard let target, appliedTargetID != target.id else { return }
        appliedTargetID = target.id
        selection = .prayers
        viewModel.navigate(to: target)
    }
}
