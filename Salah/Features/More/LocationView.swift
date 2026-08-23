import SwiftUI

struct LocationView: View {
    @Bindable var container: AppContainer
    @State private var showingDistricts = false
    @State private var showingLocationEducation = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Current", value: container.localizedLocationName)
                LabeledContent("Source", value: container.settings.location.source.title)
                LabeledContent("Permission", value: container.locationProvider.authorization.title)
                Button("Use Current Location") { showingLocationEducation = true }
                Button("Choose District Manually") { showingDistricts = true }
            } header: {
                Text("Prayer Location")
            } footer: {
                Text("Location is used only to calculate prayer times on this device. Approximate When In Use access is sufficient.")
            }
        }
        .navigationTitle("Location")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
        .sheet(isPresented: $showingDistricts) {
            NavigationStack {
                DistrictPickerView(districts: container.districts) { district in
                    showingDistricts = false
                    updateLocation(district.prayerLocation)
                }
            }
        }
        .sheet(isPresented: $showingLocationEducation) {
            CurrentLocationSettingsSheet(container: container) { location in
                showingLocationEducation = false
                updateLocation(location)
            }
            .presentationDetents([.medium, .large])
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
