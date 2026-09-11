import Charts
import SwiftUI

private enum InsightCategory: String, CaseIterable, Identifiable {
    case salah
    case tasbih
    case nafl
    case charity

    var id: Self { self }

    var title: String {
        switch self {
        case .salah: L10n.string("Salah")
        case .tasbih: L10n.string("Tasbih")
        case .nafl: L10n.string("Nafl")
        case .charity: L10n.string("Charity")
        }
    }

    var symbol: String {
        switch self {
        case .salah: "checkmark.circle.fill"
        case .tasbih: "circle.hexagongrid.fill"
        case .nafl: "sparkles"
        case .charity: "heart.fill"
        }
    }
}

private enum InsightDatePreset: String, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths
    case sixMonths
    case year
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .week: L10n.string("Last 7 Days")
        case .month: L10n.string("This Month")
        case .threeMonths: L10n.string("Last 3 Months")
        case .sixMonths: L10n.string("Last 6 Months")
        case .year: L10n.string("This Year")
        case .custom: L10n.string("Custom Range")
        }
    }
}

private struct InsightDateSelection: Equatable {
    var preset: InsightDatePreset = .month
    var customStart = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    var customEnd = Date.now

    func bounds(timeZone: TimeZone, now: Date = .now) -> ClosedRange<LocalDay> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = LocalDay(now, timeZone: timeZone)

        let startDate: Date
        switch preset {
        case .week:
            startDate = calendar.date(byAdding: .day, value: -6, to: now) ?? now
        case .month:
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .threeMonths:
            startDate = calendar.date(byAdding: .month, value: -3, to: now).flatMap {
                calendar.date(byAdding: .day, value: 1, to: $0)
            } ?? now
        case .sixMonths:
            startDate = calendar.date(byAdding: .month, value: -6, to: now).flatMap {
                calendar.date(byAdding: .day, value: 1, to: $0)
            } ?? now
        case .year:
            startDate = calendar.date(from: calendar.dateComponents([.year], from: now)) ?? now
        case .custom:
            let orderedStart = min(customStart, customEnd)
            let orderedEnd = max(customStart, customEnd)
            return LocalDay(orderedStart, timeZone: timeZone)...LocalDay(min(orderedEnd, now), timeZone: timeZone)
        }
        return LocalDay(startDate, timeZone: timeZone)...today
    }

    func title(timeZone: TimeZone) -> String {
        guard preset == .custom else { return preset.title }
        let bounds = bounds(timeZone: timeZone)
        let start = bounds.lowerBound.date(in: timeZone) ?? customStart
        let end = bounds.upperBound.date(in: timeZone) ?? customEnd
        let style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: L10n.locale, timeZone: timeZone)
        return "\(start.formatted(style)) – \(end.formatted(style))"
    }
}

private struct InsightPlotValue: Identifiable {
    let date: Date
    let value: Double
    let detail: String

    var id: Date { date }
}

private struct InsightsDataSet {
    let prayerRecords: [PrayerRecordSnapshot]
    let tasbihRecords: [TasbihDailyRecord]
    let naflRecords: [NaflDailyRecord]
    let charityEntries: [CharityEntry]
    let charityGoal: Int
    let currencyCode: String
    let timeZone: TimeZone

    func days(in selection: InsightDateSelection) -> [LocalDay] {
        let bounds = selection.bounds(timeZone: timeZone)
        var values: [LocalDay] = []
        var cursor = bounds.lowerBound
        while cursor <= bounds.upperBound {
            values.append(cursor)
            cursor = cursor.adding(days: 1, in: timeZone)
        }
        return values
    }

    func contains(_ day: LocalDay, in selection: InsightDateSelection) -> Bool {
        selection.bounds(timeZone: timeZone).contains(day)
    }

    func date(for day: LocalDay) -> Date {
        day.date(in: timeZone) ?? .now
    }

    func prayerValues(in selection: InsightDateSelection) -> [InsightPlotValue] {
        let completed = prayerRecords.filter(\.completed)
        return aggregateDaily(days(in: selection).map { day in
            let count = Set(completed.filter { $0.localDay == day }.map(\.prayer)).count
            return (day, Double(count))
        }, unit: L10n.string("prayers"))
    }

    func tasbihValues(in selection: InsightDateSelection) -> [InsightPlotValue] {
        aggregateDaily(days(in: selection).map { day in
            let count = tasbihRecords.first(where: { $0.day == day })?.count ?? 0
            return (day, Double(count))
        }, unit: L10n.string("counts"))
    }

    func naflValues(in selection: InsightDateSelection) -> [InsightPlotValue] {
        aggregateDaily(days(in: selection).map { day in
            let count = naflRecords.first(where: { $0.day == day })?.completedCount ?? 0
            return (day, Double(count))
        }, unit: L10n.string("practices"))
    }

    func charityValues(in selection: InsightDateSelection) -> [InsightPlotValue] {
        let bounds = selection.bounds(timeZone: timeZone)
        let entries = charityEntries.filter {
            $0.currencyCode == currencyCode && bounds.contains(LocalDay($0.date, timeZone: timeZone))
        }
        let grouped = Dictionary(grouping: entries) { entry -> LocalDay in
            let local = LocalDay(entry.date, timeZone: timeZone)
            return LocalDay(year: local.year, month: local.month, day: 1)
        }
        return grouped.keys.sorted().map { month in
            let total = grouped[month, default: []].reduce(0) { $0 + $1.amount }
            return InsightPlotValue(
                date: date(for: month),
                value: total,
                detail: total.formatted(.currency(code: currencyCode).locale(L10n.locale))
            )
        }
    }

    private func aggregateDaily(_ values: [(LocalDay, Double)], unit: String) -> [InsightPlotValue] {
        let chunkSize = values.count <= 31 ? 1 : values.count <= 180 ? 7 : 30
        return stride(from: 0, to: values.count, by: chunkSize).map { start in
            let chunk = Array(values[start..<min(start + chunkSize, values.count)])
            let total = chunk.reduce(0) { $0 + $1.1 }
            let day = chunk.first?.0 ?? LocalDay(.now, timeZone: timeZone)
            return InsightPlotValue(
                date: date(for: day),
                value: total,
                detail: "\(Int(total).formatted(.number.locale(L10n.locale))) \(unit)"
            )
        }
    }
}

struct InsightsView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var selection = InsightDateSelection()
    @State private var prayerRecords: [PrayerRecordSnapshot] = []
    @State private var tasbihRecords: [TasbihDailyRecord] = []
    @State private var naflRecords: [NaflDailyRecord] = []
    @State private var charityEntries: [CharityEntry] = []
    @AppStorage("salah.deeds.charity-goal") private var charityGoal = 100
    @AppStorage(CharityCurrency.storageKey) private var charityCurrencyCode = CharityCurrency.code()

    private var data: InsightsDataSet {
        InsightsDataSet(
            prayerRecords: prayerRecords,
            tasbihRecords: tasbihRecords,
            naflRecords: naflRecords,
            charityEntries: charityEntries,
            charityGoal: charityGoal,
            currencyCode: charityCurrencyCode,
            timeZone: container.settings.location.timeZone
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                overviewHeader
                summaryCard(for: .salah)
                summaryCard(for: .tasbih)
                summaryCard(for: .nafl)
                summaryCard(for: .charity)
            }
            .padding()
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InsightDateFilterButton(selection: $selection, timeZone: container.settings.location.timeZone)
            }
        }
        .task { refresh() }
        .onAppear { refresh() }
    }

    private var overviewHeader: some View {
        SalahCard(isTransparent: true) {
            Label(selection.title(timeZone: data.timeZone), systemImage: "calendar")
                .font(.headline)
            Text("A private reflection across everything you track.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.84))
            Text("Recorded activity is shown without ranking or judgment.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.72))
        }
        .foregroundStyle(.white)
        .background(palette.heroGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func summaryCard(for category: InsightCategory) -> some View {
        let summary = summary(for: category)
        InsightSummaryCard(
            category: category,
            primaryValue: summary.primary,
            primaryLabel: summary.primaryLabel,
            secondaryValue: summary.secondary,
            secondaryLabel: summary.secondaryLabel,
            values: values(for: category),
            accent: palette.accent
        ) {
            InsightDetailView(category: category, container: container, initialSelection: selection, data: data)
        }
    }

    private func summary(for category: InsightCategory) -> (primary: String, primaryLabel: String, secondary: String, secondaryLabel: String) {
        let bounds = selection.bounds(timeZone: data.timeZone)
        switch category {
        case .salah:
            let completed = data.prayerRecords.filter { $0.completed && bounds.contains($0.localDay) }.count
            let possible = prayerPossibleCount
            let percentage = possible == 0 ? 0 : Double(completed) / Double(possible)
            let streak = TrackerInsightCalculator.calculate(
                records: data.prayerRecords,
                today: LocalDay(.now, timeZone: data.timeZone),
                timeZone: data.timeZone
            ).currentStreak
            return (percentage.formatted(.percent.precision(.fractionLength(0)).locale(L10n.locale)), L10n.string("recorded"), streak.formatted(.number.locale(L10n.locale)), L10n.string("day full streak"))
        case .tasbih:
            let records = data.tasbihRecords.filter { bounds.contains($0.day) }
            return (records.reduce(0) { $0 + $1.count }.formatted(.number.locale(L10n.locale)), L10n.string("counts"), records.filter { $0.count > 0 }.count.formatted(.number.locale(L10n.locale)), L10n.string("active days"))
        case .nafl:
            let records = data.naflRecords.filter { bounds.contains($0.day) }
            return (records.reduce(0) { $0 + $1.completedCount }.formatted(.number.locale(L10n.locale)), L10n.string("practices recorded"), records.filter { $0.completedCount > 0 }.count.formatted(.number.locale(L10n.locale)), L10n.string("active days"))
        case .charity:
            let entries = data.charityEntries.filter {
                $0.currencyCode == data.currencyCode && bounds.contains(LocalDay($0.date, timeZone: data.timeZone))
            }
            let total = entries.reduce(0) { $0 + $1.amount }
            return (total.formatted(.currency(code: data.currencyCode).locale(L10n.locale)), L10n.string("given"), entries.count.formatted(.number.locale(L10n.locale)), L10n.string("gifts"))
        }
    }

    private var prayerPossibleCount: Int {
        let selectedBounds = selection.bounds(timeZone: data.timeZone)
        guard let first = data.prayerRecords.filter(\.completed).map(\.localDay).min() else { return 0 }
        let start = max(first, selectedBounds.lowerBound)
        guard start <= selectedBounds.upperBound else { return 0 }
        var count = 0
        var cursor = start
        while cursor <= selectedBounds.upperBound {
            count += PrayerType.allCases.count
            cursor = cursor.adding(days: 1, in: data.timeZone)
        }
        return count
    }

    private func values(for category: InsightCategory) -> [InsightPlotValue] {
        switch category {
        case .salah: data.prayerValues(in: selection)
        case .tasbih: data.tasbihValues(in: selection)
        case .nafl: data.naflValues(in: selection)
        case .charity: data.charityValues(in: selection)
        }
    }

    private func refresh() {
        prayerRecords = (try? container.trackingRepository.allRecords()) ?? []
        tasbihRecords = (try? container.trackerHistoryRepository.tasbihRecords()) ?? []
        naflRecords = (try? container.trackerHistoryRepository.naflRecords()) ?? []
        charityEntries = (try? container.trackerHistoryRepository.charityEntries()) ?? []
    }
}

private struct InsightSummaryCard<Destination: View>: View {
    let category: InsightCategory
    let primaryValue: String
    let primaryLabel: String
    let secondaryValue: String
    let secondaryLabel: String
    let values: [InsightPlotValue]
    let accent: Color
    @ViewBuilder let destination: Destination

    var body: some View {
        SalahCard {
            HStack {
                Label(category.title, systemImage: category.symbol)
                    .font(.headline)
                    .foregroundStyle(accent)
                Spacer()
                NavigationLink {
                    destination
                } label: {
                    Label("Details", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 20) {
                insightMetric(primaryValue, label: primaryLabel)
                insightMetric(secondaryValue, label: secondaryLabel)
            }

            if values.contains(where: { $0.value > 0 }) {
                InteractiveInsightChart(values: values, accent: accent, compact: true)
            } else {
                Text("No activity recorded in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func insightMetric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InteractiveInsightChart: View {
    let values: [InsightPlotValue]
    let accent: Color
    var compact = false
    @State private var selectedDate: Date?

    private var selectedValue: InsightPlotValue? {
        guard let selectedDate else { return nil }
        return values.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Chart {
                ForEach(values) { value in
                    BarMark(
                        x: .value("Date", value.date, unit: .day),
                        y: .value("Recorded", value.value)
                    )
                    .foregroundStyle(selectedValue?.id == value.id ? accent : accent.opacity(0.58))
                    .cornerRadius(4)
                    .accessibilityLabel(value.date.formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale)))
                    .accessibilityValue(value.detail)
                }

                if let selectedValue {
                    RuleMark(x: .value("Selected", selectedValue.date, unit: .day))
                        .foregroundStyle(accent)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: compact ? 4 : 6)) { _ in
                    AxisGridLine().foregroundStyle(.clear)
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { event in
                                    selectValue(at: event.location, proxy: proxy, geometry: geometry)
                                }
                        )
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("insights.chart")
            .accessibilityLabel("Interactive activity chart")
            .accessibilityHint("Swipe through the chart to hear values by date")

            if let selectedValue {
                Text(
                    "\(selectedValue.date.formatted(.dateTime.year().month(.abbreviated).day().locale(L10n.locale)))  ·  \(selectedValue.detail)"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Color(uiColor: .secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
                .padding(.top, 4)
                .allowsHitTesting(false)
                .accessibilityIdentifier("insights.selection.detail")
            }
        }
        .frame(height: compact ? 125 : 260)
    }

    private func selectValue(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotRect = geometry[plotFrame]
        let plotX = location.x - plotRect.origin.x
        guard plotX >= 0, plotX <= plotRect.width,
              let date: Date = proxy.value(atX: plotX) else { return }
        selectedDate = date
    }
}

private struct InsightDetailView: View {
    let category: InsightCategory
    @Bindable var container: AppContainer
    let data: InsightsDataSet
    @Environment(\.salahPalette) private var palette
    @State private var selection: InsightDateSelection

    init(category: InsightCategory, container: AppContainer, initialSelection: InsightDateSelection, data: InsightsDataSet) {
        self.category = category
        self.container = container
        self.data = data
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                rangeHeader
                metricGrid
                chartCard
                breakdown
            }
            .padding()
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InsightDateFilterButton(selection: $selection, timeZone: data.timeZone)
            }
        }
    }

    private var rangeHeader: some View {
        HStack {
            Label(selection.title(timeZone: data.timeZone), systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Private on this device")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                SalahCard {
                    Text(metric.value)
                        .font(.title2.bold().monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Text(metric.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var chartCard: some View {
        SalahCard {
            Text(chartTitle).font(.headline)
            if chartValues.contains(where: { $0.value > 0 }) {
                InteractiveInsightChart(values: chartValues, accent: palette.accent)
            } else {
                ContentUnavailableView {
                    Label("No activity", systemImage: category.symbol)
                } description: {
                    Text("Nothing has been recorded for this date range.")
                }
                .frame(minHeight: 240)
            }
        }
    }

    @ViewBuilder
    private var breakdown: some View {
        switch category {
        case .salah:
            SalahCard {
                Text("Prayer consistency").font(.headline)
                ForEach(PrayerType.allCases) { prayer in
                    breakdownRow(
                        title: prayer.title,
                        symbol: prayer.symbol,
                        value: data.prayerRecords.filter {
                            $0.completed && $0.prayer == prayer && selection.bounds(timeZone: data.timeZone).contains($0.localDay)
                        }.count.formatted(.number.locale(L10n.locale))
                    )
                }
            }
        case .tasbih:
            SalahCard {
                Text("Daily reflection").font(.headline)
                Text("Counts are preserved even when the live counter is reset or a goal is completed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .nafl:
            SalahCard {
                Text("Practices recorded").font(.headline)
                ForEach(NaflPractice.allCases) { practice in
                    breakdownRow(
                        title: practice.title,
                        symbol: practice.symbol,
                        value: data.naflRecords.filter {
                            selection.bounds(timeZone: data.timeZone).contains($0.day) && $0.contains(practice)
                        }.count.formatted(.number.locale(L10n.locale))
                    )
                }
                Text("Nafl is shown for reflection, never as a required score.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .charity:
            SalahCard {
                Text("By purpose").font(.headline)
                let entries = filteredCharityEntries
                if entries.isEmpty {
                    Text("No giving recorded in this range.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(CharityCategory.allCases) { category in
                        let total = entries.filter { $0.category == category }.reduce(0) { $0 + $1.amount }
                        if total > 0 {
                            breakdownRow(title: category.title, symbol: category.symbol, value: total.formatted(.currency(code: data.currencyCode).locale(L10n.locale)))
                        }
                    }
                }
                Text("Amounts in different currencies are never combined.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartValues: [InsightPlotValue] {
        switch category {
        case .salah: data.prayerValues(in: selection)
        case .tasbih: data.tasbihValues(in: selection)
        case .nafl: data.naflValues(in: selection)
        case .charity: data.charityValues(in: selection)
        }
    }

    private var chartTitle: String {
        switch category {
        case .salah: L10n.string("Prayers recorded over time")
        case .tasbih: L10n.string("Counts over time")
        case .nafl: L10n.string("Practices over time")
        case .charity: L10n.string("Monthly giving")
        }
    }

    private var metrics: [(value: String, label: String)] {
        let bounds = selection.bounds(timeZone: data.timeZone)
        switch category {
        case .salah:
            let records = data.prayerRecords.filter { $0.completed && bounds.contains($0.localDay) }
            let fullDays = Dictionary(grouping: records, by: \.localDay).values.filter { Set($0.map(\.prayer)).count == 5 }.count
            return [
                (records.count.formatted(.number.locale(L10n.locale)), L10n.string("prayers recorded")),
                (fullDays.formatted(.number.locale(L10n.locale)), L10n.string("full days")),
                (Set(records.map(\.localDay)).count.formatted(.number.locale(L10n.locale)), L10n.string("active days")),
                (TrackerInsightCalculator.calculate(records: data.prayerRecords, today: LocalDay(.now, timeZone: data.timeZone), timeZone: data.timeZone).bestStreak.formatted(.number.locale(L10n.locale)), L10n.string("best full streak"))
            ]
        case .tasbih:
            let records = data.tasbihRecords.filter { bounds.contains($0.day) }
            let total = records.reduce(0) { $0 + $1.count }
            let active = records.filter { $0.count > 0 }
            let average = active.isEmpty ? 0 : total / active.count
            let goals = records.filter { $0.goal > 0 && $0.count >= $0.goal }.count
            return [
                (total.formatted(.number.locale(L10n.locale)), L10n.string("total counts")),
                (active.count.formatted(.number.locale(L10n.locale)), L10n.string("active days")),
                (average.formatted(.number.locale(L10n.locale)), L10n.string("average per active day")),
                (goals.formatted(.number.locale(L10n.locale)), L10n.string("daily goals reached"))
            ]
        case .nafl:
            let records = data.naflRecords.filter { bounds.contains($0.day) }
            let total = records.reduce(0) { $0 + $1.completedCount }
            let active = records.filter { $0.completedCount > 0 }
            let average = active.isEmpty ? 0 : Double(total) / Double(active.count)
            let mostFrequent = NaflPractice.allCases.max { lhs, rhs in
                records.filter { $0.contains(lhs) }.count < records.filter { $0.contains(rhs) }.count
            }
            let mostFrequentTitle: String
            if let mostFrequent, records.contains(where: { $0.contains(mostFrequent) }) {
                mostFrequentTitle = mostFrequent.title
            } else {
                mostFrequentTitle = "—"
            }
            return [
                (total.formatted(.number.locale(L10n.locale)), L10n.string("practices recorded")),
                (active.count.formatted(.number.locale(L10n.locale)), L10n.string("active days")),
                (average.formatted(.number.precision(.fractionLength(1)).locale(L10n.locale)), L10n.string("average on active days")),
                (mostFrequentTitle, L10n.string("most recorded"))
            ]
        case .charity:
            let entries = filteredCharityEntries
            let total = entries.reduce(0) { $0 + $1.amount }
            let categories = Set(entries.map(\.category)).count
            return [
                (total.formatted(.currency(code: data.currencyCode).locale(L10n.locale)), L10n.string("given")),
                (entries.count.formatted(.number.locale(L10n.locale)), L10n.string("gifts")),
                (Double(data.charityGoal).formatted(.currency(code: data.currencyCode).locale(L10n.locale)), L10n.string("monthly intention")),
                (categories.formatted(.number.locale(L10n.locale)), L10n.string("purposes"))
            ]
        }
    }

    private var filteredCharityEntries: [CharityEntry] {
        let bounds = selection.bounds(timeZone: data.timeZone)
        return data.charityEntries.filter {
            $0.currencyCode == data.currencyCode && bounds.contains(LocalDay($0.date, timeZone: data.timeZone))
        }
    }

    private func breakdownRow(title: String, symbol: String, value: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

private struct InsightDateFilterButton: View {
    @Binding var selection: InsightDateSelection
    let timeZone: TimeZone
    @State private var showingCustomRange = false
    @State private var draftStart = Date.now
    @State private var draftEnd = Date.now

    var body: some View {
        Menu {
            ForEach(InsightDatePreset.allCases.filter { $0 != .custom }) { preset in
                Button {
                    selection.preset = preset
                } label: {
                    if selection.preset == preset {
                        Label(preset.title, systemImage: "checkmark")
                    } else {
                        Text(preset.title)
                    }
                }
            }
            Divider()
            Button {
                draftStart = selection.customStart
                draftEnd = selection.customEnd
                showingCustomRange = true
            } label: {
                Label("Custom Range", systemImage: "calendar.badge.clock")
            }
        } label: {
            Label("Filter by date", systemImage: "calendar")
        }
        .accessibilityLabel("Filter insights by date")
        .sheet(isPresented: $showingCustomRange) {
            NavigationStack {
                Form {
                    DatePicker("Start", selection: $draftStart, in: ...Date.now, displayedComponents: .date)
                    DatePicker("End", selection: $draftEnd, in: ...Date.now, displayedComponents: .date)
                }
                .navigationTitle("Custom Range")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingCustomRange = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            selection.customStart = min(draftStart, draftEnd)
                            selection.customEnd = max(draftStart, draftEnd)
                            selection.preset = .custom
                            showingCustomRange = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}
