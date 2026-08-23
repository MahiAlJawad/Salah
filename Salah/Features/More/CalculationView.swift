import SwiftUI

struct CalculationView: View {
    @Bindable var container: AppContainer

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: calculationBinding(\.method)) {
                    ForEach(CalculationMethod.allCases) { method in Text(method.title).tag(method) }
                }
                Picker("Asr calculation", selection: calculationBinding(\.madhab)) {
                    ForEach(Madhab.allCases) { madhab in Text(madhab.title).tag(madhab) }
                }
                Stepper("Hijri adjustment: \(signed(container.settings.calculation.hijriAdjustment)) day", value: calculationBinding(\.hijriAdjustment), in: -2...2)
                Stepper("Safety adjustment: \(container.settings.calculation.cautionMinutes) min", value: calculationBinding(\.cautionMinutes), in: 0...10)
                Picker("Time format", selection: calculationBinding(\.timeFormat)) {
                    ForEach(TimeFormatPreference.allCases) { format in Text(format.title).tag(format) }
                }
            } header: {
                Text("Calculation")
            } footer: {
                Text("Safety adjustment ends Sahri earlier and begins Maghrib and Iftar later. Published times may differ; confirm with an appropriate local authority when necessary.")
            }
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
}
