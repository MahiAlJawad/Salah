import SwiftUI

struct CharityHistoryView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @AppStorage("salah.deeds.charity-total") private var legacyTotal = 0
    @AppStorage("salah.deeds.charity-goal") private var charityGoal = 100
    @AppStorage(CharityCurrency.storageKey) private var currencyCode = CharityCurrency.code()
    @State private var entries: [CharityEntry] = []
    @State private var showingAddEntry = false
    @State private var showingGoalEditor = false

    private var monthlyTotal: Double {
        CharityLedger.total(entries.filter { $0.currencyCode == currencyCode }, inMonthContaining: .now)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Given this month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(monthlyTotal, format: .currency(code: currencyCode))
                        .font(.largeTitle.bold().monospacedDigit())
                    ProgressView(value: min(monthlyTotal, Double(charityGoal)), total: Double(max(1, charityGoal)))
                    Button("Edit Monthly Intention", systemImage: "target") { showingGoalEditor = true }
                }
                .padding(.vertical, 6)

                Button("Add Giving", systemImage: "plus.circle.fill") { showingAddEntry = true }

                NavigationLink {
                    RemindersView(container: container)
                } label: {
                    Label("Charity Reminder", systemImage: "bell.badge.fill")
                        .foregroundStyle(palette.accent)
                }
            }

            Section {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No giving recorded", systemImage: "heart")
                    } description: {
                        Text("Add a private entry after you give.")
                    }
                } else {
                    ForEach(entries) { entry in
                        CharityEntryRow(entry: entry)
                    }
                    .onDelete(perform: deleteEntries)
                }
            } header: {
                Text("Giving History")
            } footer: {
                Text("Entries stay on this device. Swipe an entry to delete it.")
            }
        }
        .navigationTitle("Sadaqah")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Giving", systemImage: "plus") { showingAddEntry = true }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddCharityEntryView(currencyCode: $currencyCode, onSave: addEntry)
        }
        .sheet(isPresented: $showingGoalEditor) {
            CharityGoalEditor(goal: charityGoal, currencyCode: currencyCode) {
                charityGoal = $0
            }
        }
        .task { refresh() }
        .onAppear { refresh() }
    }

    private func addEntry(_ entry: CharityEntry) {
        try? container.trackerHistoryRepository.addCharityEntry(entry)
        refresh()
        updateLegacyTotal()
    }

    private func deleteEntries(at offsets: IndexSet) {
        let ids = Set(offsets.compactMap { entries.indices.contains($0) ? entries[$0].id : nil })
        try? container.trackerHistoryRepository.deleteCharityEntries(ids: ids)
        refresh()
        updateLegacyTotal()
    }

    private func refresh() {
        entries = (try? container.trackerHistoryRepository.charityEntries()) ?? []
    }

    private func updateLegacyTotal() {
        legacyTotal = Int(
            CharityLedger.total(
                entries.filter { $0.currencyCode == currencyCode },
                inMonthContaining: .now
            ).rounded()
        )
    }
}

struct CharityEntryRow: View {
    let entry: CharityEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.symbol)
                .foregroundStyle(.pink)
                .frame(width: 30, height: 30)
                .background(Color.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.recipient.isEmpty ? entry.category.title : entry.recipient)
                    .font(.subheadline.weight(.semibold))
                Text(entry.date, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(entry.amount, format: .currency(code: entry.currencyCode))
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

struct AddCharityEntryView: View {
    @Binding var currencyCode: String
    let onSave: (CharityEntry) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var date = Date.now
    @State private var category = CharityCategory.sadaqah
    @State private var recipient = ""
    @State private var note = ""

    private var amount: Double? {
        let separator = L10n.locale.decimalSeparator ?? "."
        let normalized = amountText.replacingOccurrences(of: separator, with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var presets: [Int] {
        currencyCode == "BDT" ? [100, 500, 1_000, 2_000] : [5, 10, 25, 50]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    NavigationLink {
                        CharityCurrencyPicker(selection: $currencyCode)
                    } label: {
                        LabeledContent("Currency", value: currencyCode)
                    }

                    TextField("0", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())
                        .accessibilityLabel("Giving amount in \(currencyCode)")

                    HStack {
                        ForEach(presets, id: \.self) { preset in
                            Button(preset.formatted(.number.locale(L10n.locale))) { amountText = String(preset) }
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                Section("Details") {
                    DatePicker("Date given", selection: $date, in: ...Date.now, displayedComponents: .date)
                    Picker("Purpose", selection: $category) {
                        ForEach(CharityCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    TextField("Organization or recipient (optional)", text: $recipient)
                    TextField("Private note (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Text("This records a private reflection only. Salah does not send money or contact the recipient.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Add Giving")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount else { return }
                        onSave(CharityEntry(
                            amount: amount,
                            date: date,
                            category: category,
                            currencyCode: currencyCode,
                            recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .disabled(amount == nil)
                }
            }
        }
    }
}

private struct CharityCurrencyPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var options: [CharityCurrency.Option] {
        CharityCurrency.filteredOptions(matching: searchText)
    }

    var body: some View {
        List(options) { option in
            Button {
                selection = option.code
                dismiss()
            } label: {
                HStack {
                    Text(option.code)
                    Spacer()
                    if option.code == selection {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Country or currency code")
        .overlay {
            if options.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }
}

struct CharityGoalEditor: View {
    let goal: Int
    let currencyCode: String
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var goalText = ""

    private var parsedGoal: Int? {
        guard let value = Int(goalText), (1...10_000_000).contains(value) else { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Monthly intention", text: $goalText)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                } header: {
                    Text("Amount in \(currencyCode)")
                } footer: {
                    Text("An intention is a private guide, not a payment or pledge.")
                }
            }
            .navigationTitle("Monthly Intention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parsedGoal else { return }
                        onSave(parsedGoal)
                        dismiss()
                    }
                    .disabled(parsedGoal == nil)
                }
            }
            .onAppear { goalText = String(goal) }
        }
    }
}
