import Observation
import SwiftUI

@MainActor
@Observable
final class TodayViewModel {
    private let repository: any PrayerTimesRepository
    private let trackingRepository: any PrayerTrackingRepository
    private let trackerHistoryRepository: any TrackerHistoryRepository
    private let settings: AppSettings

    var state: FeatureLoadState<PrayerDay> = .idle
    var previousDay: PrayerDay?
    var completed: Set<PrayerType> = []
    var naflCompletedMask = 0
    private var requestID = UUID()

    init(container: AppContainer) {
        repository = container.prayerTimesRepository
        trackingRepository = container.trackingRepository
        trackerHistoryRepository = container.trackerHistoryRepository
        settings = container.settings
    }

    func load(day: LocalDay, policy: CachePolicy = .cacheFirst) async {
        let token = UUID()
        requestID = token
        state = .loading
        let location = settings.location
        let calculation = settings.calculation
        do {
            async let main = repository.day(
                for: PrayerTimesQuery(day: day, location: location, settings: calculation),
                location: location,
                policy: policy
            )
            let priorLocalDay = day.adding(days: -1, in: location.timeZone)
            let tomorrowLocalDay = day.adding(days: 1, in: location.timeZone)
            async let prior = try? repository.day(
                for: PrayerTimesQuery(day: priorLocalDay, location: location, settings: calculation),
                location: location,
                policy: .cacheFirst
            )
            async let tomorrow = try? repository.day(
                for: PrayerTimesQuery(day: tomorrowLocalDay, location: location, settings: calculation),
                location: location,
                policy: .cacheFirst
            )
            async let future = additionalWidgetDays(
                after: day,
                location: location,
                calculation: calculation
            )
            let loaded = try await main
            let priorLoaded = await prior
            let tomorrowLoaded = await tomorrow
            let futureDays = await future
            guard requestID == token else { return }
            previousDay = priorLoaded?.value
            completed = (try? trackingRepository.completedPrayerTypes(on: day)) ?? []
            naflCompletedMask = (try? trackerHistoryRepository.naflRecord(on: day)?.completedMask) ?? 0
            WidgetDataPublisher.save(
                prayerDay: loaded.value,
                completed: completed,
                naflCompletedMask: naflCompletedMask,
                nextDay: tomorrowLoaded?.value,
                futureDays: futureDays
            )
            state = loaded.isStale
                ? .offline(loaded.value, lastUpdated: loaded.value.fetchedAt)
                : .loaded(loaded.value, source: loaded.source)
        } catch is CancellationError {
            if requestID == token { state = .failed(.cancelled) }
        } catch let error as PrayerDataError {
            if requestID == token { state = .failed(error) }
        } catch {
            if requestID == token { state = .failed(.transport(error.localizedDescription)) }
        }
    }

    /// The widget needs a local schedule beyond tomorrow because WidgetKit may
    /// not ask the app for fresh data every day. Prayer times are calculated
    /// on-device, so extending this horizon does not make network requests.
    private func additionalWidgetDays(
        after day: LocalDay,
        location: PrayerLocation,
        calculation: CalculationSettings
    ) async -> [PrayerDay] {
        var days: [PrayerDay] = []
        for offset in 2...7 {
            let futureDay = day.adding(days: offset, in: location.timeZone)
            guard let loaded = try? await repository.day(
                for: PrayerTimesQuery(day: futureDay, location: location, settings: calculation),
                location: location,
                policy: .cacheFirst
            ) else { continue }
            days.append(loaded.value)
        }
        return days
    }

    func toggle(_ prayer: PrayerType, on day: LocalDay, timeZone: TimeZone, source: String = "today") {
        let newValue = !completed.contains(prayer)
        do {
            try trackingRepository.setCompleted(newValue, prayer: prayer, day: day, timeZone: timeZone, source: source)
            if newValue { completed.insert(prayer) } else { completed.remove(prayer) }
            WidgetDataPublisher.updateCompletion(prayer: prayer, day: day, completed: newValue)
        } catch { }
    }
}

struct TodayView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel: TodayViewModel
    @State private var showingLocationPicker = false
    @State private var showingFutureSalahAlert = false
    #if DEBUG
    @AppStorage("salah.debug.current-prayer-preview") private var currentPrayerPreview = ""
    #endif

    init(container: AppContainer) {
        self.container = container
        _viewModel = State(initialValue: TodayViewModel(container: container))
    }

    private var queryIdentity: String {
        PrayerTimesQuery(
            day: container.router.selectedDay,
            location: container.settings.location,
            settings: container.settings.calculation
        ).cacheKey
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading prayer times…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let day, _):
                dashboard(day: day, offlineDate: nil)
            case let .offline(day, lastUpdated):
                dashboard(day: day, offlineDate: lastUpdated)
            case .failed(let error):
                PrayerDataUnavailableView(error: error) {
                    await viewModel.load(day: container.router.selectedDay, policy: .reload)
                }
            case .empty:
                ContentUnavailableView("No prayer times", systemImage: "calendar.badge.exclamationmark")
            case .permissionDenied:
                LocationEducationView(container: container)
            }
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Change Location", systemImage: "map.fill") {
                        showingLocationPicker = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                        Text(container.localizedLocationName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Prayer location, \(container.localizedLocationName)")
                .accessibilityHint("Shows options to change the prayer location")
                .accessibilityIdentifier("today.location.menu")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RemindersView(container: container)
                } label: {
                    Label("Prayer reminders", systemImage: "bell")
                }
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            GlobalLocationPickerView(container: container) { location in
                showingLocationPicker = false
                updateLocation(location)
            }
        }
        .alert("Future Salah is not trackable", isPresented: $showingFutureSalahAlert) {
            Button("OK", role: .cancel) { }
        }
        .task(id: queryIdentity) {
            await viewModel.load(day: container.router.selectedDay)
        }
        .task {
            while !Task.isCancelled {
                container.router.syncSelectedDayToNow(timeZone: container.settings.location.timeZone)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    @ViewBuilder
    private func dashboard(day: PrayerDay, offlineDate: Date?) -> some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let offlineDate { OfflineBanner(lastUpdated: offlineDate) }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(day.gregorianSummary).font(.headline)
                        Text(day.hijriSummary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if day.localDay != LocalDay(.now, timeZone: day.timeZone) {
                        Button("Today") { container.router.showToday(timeZone: container.settings.location.timeZone) }
                            .buttonStyle(.bordered)
                    }
                }

                if day.localDay == LocalDay(.now, timeZone: day.timeZone) {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        CurrentPrayerCard(
                            moment: PrayerTimeline.cardMoment(
                                now: displayedNow(for: day, fallback: context.date),
                                today: day,
                                previous: viewModel.previousDay
                            )
                        )
                    }
                } else {
                    SalahCard {
                        Label("Schedule for selected date", systemImage: "calendar")
                            .font(.headline)
                        Text("Live countdowns are shown only for today.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("PRAYER SCHEDULE")
                        .font(.footnote.bold())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Prayer Schedule")
                    Spacer()
                    PrayerCompletionSummary(viewModel: viewModel)
                }
                .padding(.horizontal, 4)

                VStack(spacing: 0) {
                    ForEach(day.windows) { window in
                        PrayerScheduleRow(
                            window: window,
                            day: day,
                            preference: container.settings.calculation.timeFormat,
                            isActive: isActive(window, day: day, now: displayedNow(for: day, fallback: .now)),
                            showsDisclosure: false
                        ) {
                            PrayerCompletionControl(viewModel: viewModel, prayer: window.prayer) {
                                handleScheduleTap(window, day: day)
                            }
                        }
                        if window.prayer != .isha { Divider().padding(.leading, 62) }
                    }
                }
                .background(palette.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                HStack(spacing: 12) {
                    eventCard(title: "Sunrise", date: day.sunrise, symbol: "sunrise.fill", tone: .sunriseAmber, day: day)
                    eventCard(title: "Sunset", date: day.sunset, symbol: "sunset.fill", tone: .sunsetCoral, day: day)
                }

                Text("FASTING")
                    .font(.footnote.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                HStack(spacing: 12) {
                    eventCard(title: "Sahri ends", date: day.sahri, symbol: "moon.stars.fill", tone: .predawnIndigo, day: day)
                    eventCard(title: "Iftar begins", date: day.iftar, symbol: "sun.horizon.fill", tone: .sunsetCoral, day: day)
                }

                Text("Times use \(day.methodName), \(container.settings.calculation.madhab.title). Confirm locally when necessary.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(palette.screenBackground)
        .refreshable {
            await viewModel.load(day: container.router.selectedDay, policy: .reload)
        }
    }

    private func isActive(_ window: PrayerWindow, day: PrayerDay, now: Date) -> Bool {
        guard day.localDay == LocalDay(.now, timeZone: day.timeZone) else { return false }
        let moment = PrayerTimeline.moment(
            now: now,
            today: day,
            previous: viewModel.previousDay
        )
        return moment.current == window
    }

    private func displayedNow(for day: PrayerDay, fallback: Date) -> Date {
        #if DEBUG
        if let prayer = PrayerType(rawValue: currentPrayerPreview),
           let window = day.window(for: prayer) {
            return window.start.addingTimeInterval(window.end.timeIntervalSince(window.start) / 2)
        }
        #endif
        return fallback
    }

    private func handleScheduleTap(_ window: PrayerWindow, day: PrayerDay, now: Date = .now) {
        if PrayerTimeline.isMidnightToFajrWindow(now: now, today: day) {
            showingFutureSalahAlert = true
            return
        }

        if window.prayer == .isha,
           PrayerTimeline.isPreviousDayIshaCarryover(now: now, today: day) {
            container.router.showPrayerInCalendar(
                day: day.localDay.adding(days: -1, in: day.timeZone),
                prayer: .isha
            )
            return
        }
        viewModel.toggle(window.prayer, on: day.localDay, timeZone: day.timeZone)
    }

    private func eventCard(title: String, date: Date, symbol: String, tone: SalahIconTone, day: PrayerDay) -> some View {
        SalahCard {
            Image(systemName: symbol)
                .foregroundStyle(tone.color(for: colorScheme))
                .accessibilityHidden(true)
            Text(L10n.dynamic(title)).font(.caption).foregroundStyle(.secondary)
            Text(PrayerDateFormatting.time(date, preference: container.settings.calculation.timeFormat, timeZone: day.timeZone))
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    private func updateLocation(_ location: PrayerLocation) {
        let oldSignature = PrayerTimesQuery(
            day: container.router.selectedDay,
            location: container.settings.location,
            settings: container.settings.calculation
        ).signature
        container.settings.location = location
        container.router.selectedDay = LocalDay(.now, timeZone: location.timeZone)
        Task {
            await container.prayerTimesRepository.invalidate(signature: oldSignature)
            await ReminderCoordinator.reconcile(container: container)
        }
    }
}
