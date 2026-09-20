import SwiftUI

struct LocationEducationView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var isRequesting = false
    @State private var errorMessage: String?
    @State private var showingLocationSearch = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "location.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Use your location?")
                .font(.largeTitle.bold())
            Text("Salah uses a one-time location request to calculate prayer times on this device. It does not track your location in the background. You can search for any city or place instead.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 14) {
                Label("When In Use access only", systemImage: "checkmark.circle.fill")
                Label("Approximate location is sufficient", systemImage: "checkmark.circle.fill")
                Label("Search for locations worldwide", systemImage: "checkmark.circle.fill")
            }
            .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Location error. \(errorMessage)")
            }
            Spacer()

            Button {
                requestLocation()
            } label: {
                if isRequesting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Use Current Location")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRequesting)

            Button("Search for a City or Place") { showingLocationSearch = true }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .sheet(isPresented: $showingLocationSearch) {
            GlobalLocationPickerView(container: container, showsCurrentLocation: false) { location in
                showingLocationSearch = false
                complete(with: location)
            }
        }
    }

    private func requestLocation() {
        isRequesting = true
        errorMessage = nil
        Task {
            do {
                let location = try await container.locationProvider.requestCurrentLocation()
                complete(with: location)
            } catch {
                errorMessage = error.localizedDescription
            }
            isRequesting = false
        }
    }

    private func complete(with location: PrayerLocation) {
        container.settings.location = location
        container.settings.locationEducationSeen = true
        container.router.selectedDay = LocalDay(.now, timeZone: location.timeZone)
        container.settings.onboardingComplete = true
    }
}
