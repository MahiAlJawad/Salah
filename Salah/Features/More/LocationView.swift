import SwiftUI

struct LocationView: View {
    @Bindable var container: AppContainer
    @State private var showingLocationPicker = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Current", value: container.localizedLocationName)
                LabeledContent("Source", value: container.settings.location.source.title)
                LabeledContent("Permission", value: container.locationProvider.authorization.title)
                Button("Change Location") { showingLocationPicker = true }
            } header: {
                Text("Prayer Location")
            } footer: {
                Text("Use one-time approximate location access or search worldwide with Apple Maps. The selected location is stored on this device.")
            }
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
        .sheet(isPresented: $showingLocationPicker) {
            GlobalLocationPickerView(container: container) { location in
                showingLocationPicker = false
                updateLocation(location)
            }
        }
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
