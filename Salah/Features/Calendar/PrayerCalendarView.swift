import Observation
import SwiftUI

@MainActor
@Observable
final class CalendarViewModel {
    private let repository: any PrayerTimesRepository
    private let tracking: any PrayerTrackingRepository
    private let settings: AppSettings
    var state: FeatureLoadState<[PrayerDay]> = .idle
    var selectedDay: LocalDay
    var monthAnchor: LocalDay
    var anchoredToToday = true
    var trackerDays: Set<LocalDay> = []
    var selectedPrayer: PrayerType?

    init(container: AppContainer) {
        repository = container.prayerTimesRepository
        tracking = container.trackingRepository
        settings = container.settings
        let today = LocalDay(.now, timeZone: settings.location.timeZone)
        selectedDay = today
        monthAnchor = LocalDay(year: today.year, month: today.month, day: 1)
    }

    func load(policy: CachePolicy = .cacheFirst) async {
        state = .loading
        do {
            let loaded = try await repository.month(
                containing: monthAnchor,
                location: settings.location,
                settings: settings.calculation,
                policy: policy
            )
            refreshTrackerDays()
            let days = loaded.map(\.value)
            if loaded.contains(where: \.isStale), let timestamp = days.map(\.fetchedAt).max() {
                state = .offline(days, lastUpdated: timestamp)
            } else {
                state = .loaded(days, source: loaded.contains { $0.source == .calculated } ? .calculated : .diskCache)
            }
        } catch let error as PrayerDataError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    func moveMonth(_ amount: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = settings.location.timeZone
        guard let date = monthAnchor.date(in: settings.location.timeZone),
              let moved = calendar.date(byAdding: .month, value: amount, to: date) else { return }
        let local = LocalDay(moved, timeZone: settings.location.timeZone)
        monthAnchor = LocalDay(year: local.year, month: local.month, day: 1)
        selectedDay = monthAnchor
        anchoredToToday = false
    }

    /// Re-reads which days have tracked prayers so month dots stay current
    /// when completions change outside `load()` (e.g. the detail sheet).
    func refreshTrackerDays() {
        trackerDays = Set((try? tracking.allRecords().filter(\.completed).map(\.localDay)) ?? [])
    }

    /// Rolls selectedDay to the current day if still anchored.
    func syncDayToNow() {
        guard anchoredToToday else { return }
        let today = LocalDay(.now, timeZone: settings.location.timeZone)
        guard selectedDay != today else { return }
        selectedDay = today
    }

    func navigate(to target: CalendarPrayerTarget) {
        selectedDay = target.day
        monthAnchor = LocalDay(year: target.day.year, month: target.day.month, day: 1)
        anchoredToToday = false
        selectedPrayer = target.prayer
    }
}

struct PrayerCalendarView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var viewModel: CalendarViewModel
    @State private var appliedTargetID: UUID?
    @State private var showingFutureSalahAlert = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(initialValue: CalendarViewModel(container: container))
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading month…")
            case .loaded(let days, _): calendar(days: days, offline: nil)
            case .offline(let days, let date): calendar(days: days, offline: date)
            case .failed(let error):
                PrayerDataUnavailableView(error: error) { await viewModel.load(policy: .reload) }
            case .empty:
                ContentUnavailableView("No calendar data", systemImage: "calendar.badge.exclamationmark")
            case .permissionDenied:
                Text("Choose a prayer location in More.")
            }
        }
        .navigationTitle("Calendar")
        .toolbar(.hidden, for: .navigationBar)
        .alert("Future Salah is not trackable", isPresented: $showingFutureSalahAlert) {
            Button("OK", role: .cancel) { }
        }
        .task(id: "\(viewModel.monthAnchor.key)|\(container.settings.location.name)|\(container.settings.calculation)|\(container.settings.language.rawValue)") {
            await viewModel.load()
        }
        .task {
            while !Task.isCancelled {
                viewModel.syncDayToNow()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        .onAppear { applyCalendarTarget(container.router.calendarPrayerTarget) }
        .onChange(of: container.router.calendarPrayerTarget) { _, target in
            applyCalendarTarget(target)
        }
    }

    private func calendar(days: [PrayerDay], offline: Date?) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                Text("Calendar")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let offline { OfflineBanner(lastUpdated: offline) }
                HStack {
                    Button { viewModel.moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Spacer()
                    Text(monthTitle).font(.title3.bold())
                    Spacer()
                    Button { viewModel.moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                }

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(localizedShortWeekdaySymbols, id: \.self) { symbol in
                        Text(symbol).font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                    ForEach(0..<leadingBlankCount, id: \.self) { _ in Color.clear.frame(height: 44) }
                    ForEach(days) { day in
                        calendarCell(day)
                    }
                }

                if let selected = days.first(where: { $0.localDay == viewModel.selectedDay }) {
                    VStack(spacing: 0) {
                        ForEach(selected.windows) { window in
                            Button {
                                if PrayerTimeline.isMidnightToFajrWindow(now: .now, today: selected) {
                                    showingFutureSalahAlert = true
                                } else {
                                    viewModel.selectedPrayer = window.prayer
                                }
                            } label: {
                                PrayerScheduleRow(
                                    window: window,
                                    day: selected,
                                    preference: container.settings.calculation.timeFormat,
                                    isActive: false,
                                    isCompleted: (try? container.trackingRepository.completedPrayerTypes(on: selected.localDay).contains(window.prayer)) ?? false
                                )
                            }
                            .buttonStyle(.plain)
                            if window.prayer != .isha { Divider().padding(.leading, 62) }
                        }
                    }
                    .background(palette.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .sheet(item: $viewModel.selectedPrayer) { prayer in
                        if let window = selected.window(for: prayer) {
                            PrayerDetailSheet(
                                window: window,
                                day: selected,
                                container: container,
                                isCompleted: (try? container.trackingRepository.completedPrayerTypes(on: selected.localDay).contains(prayer)) ?? false
                            ) {
                                let current = (try? container.trackingRepository.completedPrayerTypes(on: selected.localDay).contains(prayer)) ?? false
                                try? container.trackingRepository.setCompleted(!current, prayer: prayer, day: selected.localDay, timeZone: selected.timeZone, source: "calendar")
                                WidgetDataPublisher.updateCompletion(prayer: prayer, day: selected.localDay, completed: !current)
                                viewModel.refreshTrackerDays()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .refreshable { await viewModel.load(policy: .reload) }
        .background(palette.screenBackground)
    }

    private func calendarCell(_ day: PrayerDay) -> some View {
        let today = LocalDay(.now, timeZone: day.timeZone)
        let selected = day.localDay == viewModel.selectedDay
        let isFuture = day.localDay > today
        return Button {
            if isFuture {
                showingFutureSalahAlert = true
            } else {
                viewModel.selectedDay = day.localDay
                viewModel.anchoredToToday = (day.localDay == today)
            }
        } label: {
            ZStack(alignment: .bottom) {
                Text("\(day.localDay.day)")
                    .font(.body.weight(selected ? .bold : .regular))
                    .foregroundStyle(selected ? .white : (isFuture ? .secondary : .primary))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(selected ? palette.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        if day.localDay == today, !selected {
                            RoundedRectangle(cornerRadius: 12).stroke(palette.accent, lineWidth: 2)
                        }
                    }
                    .opacity(isFuture ? 0.4 : 1.0)
                if viewModel.trackerDays.contains(day.localDay), !isFuture {
                    Circle().fill(selected ? .white : palette.accent).frame(width: 5, height: 5).padding(.bottom, 4)
                }
            }
        }
        .accessibilityLabel("\(day.gregorianSummary)\(day.localDay == today ? ", today" : "")\(viewModel.trackerDays.contains(day.localDay) ? ", has tracker records" : "")\(isFuture ? ", future date" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var monthTitle: String {
        guard let date = viewModel.monthAnchor.date(in: container.settings.location.timeZone) else { return viewModel.monthAnchor.key }
        return date.formatted(.dateTime.month(.wide).year().locale(L10n.locale))
    }

    private var localizedShortWeekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter.shortStandaloneWeekdaySymbols
    }

    private var leadingBlankCount: Int {
        guard let date = viewModel.monthAnchor.date(in: container.settings.location.timeZone) else { return 0 }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = container.settings.location.timeZone
        return max(0, calendar.component(.weekday, from: date) - 1)
    }

    private func applyCalendarTarget(_ target: CalendarPrayerTarget?) {
        guard let target, appliedTargetID != target.id else { return }
        appliedTargetID = target.id
        viewModel.navigate(to: target)
    }
}
