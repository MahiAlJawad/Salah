import SwiftUI

struct CalculationView: View {
    @Bindable var container: AppContainer
    @State private var adjustmentInfo: CalculationAdjustmentInfo?

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: calculationBinding(\.method)) {
                    ForEach(CalculationMethod.allCases) { method in Text(method.title).tag(method) }
                }
                Picker("Asr calculation", selection: calculationBinding(\.madhab)) {
                    ForEach(Madhab.allCases) { madhab in Text(madhab.title).tag(madhab) }
                }
                adjustmentRow(
                    "Hijri adjustment: \(signed(container.settings.calculation.hijriAdjustment)) day",
                    value: calculationBinding(\.hijriAdjustment),
                    range: -2...2,
                    info: .hijri
                )
                adjustmentRow(
                    "Safety adjustment: \(container.settings.calculation.cautionMinutes) min",
                    value: calculationBinding(\.cautionMinutes),
                    range: 0...10,
                    info: .safety
                )
                Picker("Time format", selection: calculationBinding(\.timeFormat)) {
                    ForEach(TimeFormatPreference.allCases) { format in Text(format.title).tag(format) }
                }
            } header: {
                Text("Calculation")
            } footer: {
                Text("Safety adjustment ends Sahri earlier and begins Maghrib and Iftar later. Published times may differ; confirm with an appropriate local authority when necessary.")
            }
        }
        .alert(item: $adjustmentInfo) { info in
            Alert(title: Text(info.title), message: Text(info.message), dismissButton: .default(Text("OK")))
        }
        .navigationTitle("Calculation")
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

    private func adjustmentRow(
        _ title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        info: CalculationAdjustmentInfo
    ) -> some View {
        HStack {
            Stepper(title, value: value, in: range)
            CalculationAdjustmentInfoButton(info: info) { adjustmentInfo = info }
        }
    }
}

enum CalculationAdjustmentInfo: String, Identifiable {
    case hijri, safety

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hijri: L10n.string("About Hijri adjustment")
        case .safety: L10n.string("About safety adjustment")
        }
    }

    var message: String {
        switch self {
        case .hijri: L10n.string("Hijri adjustment shifts the displayed Hijri date by up to two days. It does not change prayer times.")
        case .safety: L10n.string("Safety adjustment ends Sahri earlier and starts Maghrib and Iftar later by the selected number of minutes. It does not change Fajr or Asr.")
        }
    }
}

struct CalculationAdjustmentInfoButton: View {
    let info: CalculationAdjustmentInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(info.title)
    }
}
