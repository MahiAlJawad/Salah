import SwiftUI

struct GlobalLocationPickerView: View {
    @Bindable var container: AppContainer
    let showsCurrentLocation: Bool
    let footerText: String
    let onSelect: (PrayerLocation) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var suggestions: [LocationSearchSuggestion] = []
    @State private var isSearching = false
    @State private var isResolving = false
    @State private var didSearch = false
    @State private var errorMessage: String?

    init(
        container: AppContainer,
        showsCurrentLocation: Bool = true,
        footerText: String = "Search is provided by Apple Maps. Your selected location is stored on this device.",
        onSelect: @escaping (PrayerLocation) -> Void
    ) {
        self.container = container
        self.showsCurrentLocation = showsCurrentLocation
        self.footerText = footerText
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                if showsCurrentLocation {
                    Section {
                        Button {
                            useCurrentLocation()
                        } label: {
                            Label("Use Current Location", systemImage: "location.fill")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .disabled(isResolving)
                    }
                }

                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !container.settings.recentLocations.isEmpty {
                    Section("Recent Locations") {
                        ForEach(container.settings.recentLocations, id: \.self) { location in
                            Button {
                                select(location)
                            } label: {
                                Label(location.name, systemImage: "clock.arrow.circlepath")
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                        }
                    }
                }

                if isSearching || isResolving {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView(isResolving ? "Selecting location…" : "Searching…")
                            Spacer()
                        }
                    }
                } else if let errorMessage {
                    Section {
                        ContentUnavailableView(
                            "Location Search Unavailable",
                            systemImage: "wifi.exclamationmark",
                            description: Text(errorMessage)
                        )
                        Button("Try Again") {
                            Task { await search() }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if !suggestions.isEmpty {
                    Section("Search Results") {
                        ForEach(suggestions) { suggestion in
                            Button {
                                resolve(suggestion)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(suggestion.title).foregroundStyle(.primary)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            }
                            .accessibilityIdentifier("location.search.result.\(suggestion.id)")
                        }
                    }
                } else if didSearch {
                    Section {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "City, town, or address")
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .disabled(isResolving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(L10n.dynamic(footerText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
            .task(id: query) {
                await search()
            }
        }
    }

    private func search() async {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        suggestions = []
        errorMessage = nil
        didSearch = false
        guard value.count >= 2 else {
            isSearching = false
            return
        }

        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        container.locationSearchProvider.search(value) { results, error in
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == value else { return }
            suggestions = results
            errorMessage = error
            isSearching = false
            didSearch = true
        }
    }

    private func useCurrentLocation() {
        isResolving = true
        errorMessage = nil
        Task {
            do {
                select(try await container.locationProvider.requestCurrentLocation())
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }

    private func resolve(_ suggestion: LocationSearchSuggestion) {
        isResolving = true
        errorMessage = nil
        Task {
            do {
                select(try await container.locationSearchProvider.resolve(suggestion))
            } catch {
                errorMessage = error.localizedDescription
            }
            isResolving = false
        }
    }

    private func select(_ location: PrayerLocation) {
        if location.source == .manual {
            container.settings.rememberLocation(location)
        }
        onSelect(location)
    }
}
