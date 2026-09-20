@preconcurrency import CoreLocation
@preconcurrency import MapKit
import Observation
import SwiftUI
import UIKit

enum DiscoverSection: String, CaseIterable, Identifiable {
    case mosques
    case qibla

    var id: Self { self }

    var title: String {
        switch self {
        case .mosques: L10n.string("Mosques")
        case .qibla: L10n.string("Qibla")
        }
    }
}

enum MosqueSearchOrigin {
    case current(String)
    case saved(String)
    case chosen(String)
    case mapArea

    var summary: String {
        switch self {
        case .current(let name), .saved(let name), .chosen(let name):
            String(format: L10n.string("Near %@"), name)
        case .mapArea:
            L10n.string("This map area")
        }
    }
}

@MainActor
@Observable
final class MosqueFinderViewModel {
    private let locationProvider: any LocationProviding
    private let searchProvider: any MosqueSearchProviding
    private let savedLocation: () -> PrayerLocation
    private var searchID = UUID()
    private var didStart = false
    private var lastSearchCenter: CLLocationCoordinate2D?
    private var lastSearchRegion: MKCoordinateRegion?
    private var lastOrigin: MosqueSearchOrigin?

    var places: [MosquePlace] = []
    var selectedPlaceID: String?
    var isLoading = false
    var permissionPromptVisible = false
    var didSearch = false
    var errorMessage: String?
    var fallbackMessage: String?
    var origin: MosqueSearchOrigin?
    var cameraRegion: MKCoordinateRegion
    var cameraRevision = 0

    var authorization: LocationAuthorization { locationProvider.authorization }
    var canOpenSettings: Bool { authorization == .denied }

    init(
        locationProvider: any LocationProviding,
        searchProvider: any MosqueSearchProviding,
        savedLocation: @escaping () -> PrayerLocation
    ) {
        self.locationProvider = locationProvider
        self.searchProvider = searchProvider
        self.savedLocation = savedLocation
        let location = savedLocation()
        cameraRegion = Self.region(centeredAt: location.coordinate)
    }

    convenience init(container: AppContainer) {
        self.init(
            locationProvider: container.locationProvider,
            searchProvider: container.mosqueSearchProvider,
            savedLocation: { container.settings.location }
        )
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        switch authorization {
        case .notDetermined:
            permissionPromptVisible = true
        case .authorized:
            await findNearby()
        case .denied, .restricted:
            await searchSavedLocation()
        }
    }

    func findNearby() async {
        permissionPromptVisible = false
        isLoading = true
        errorMessage = nil
        do {
            let location = try await locationProvider.requestCurrentLocation()
            await search(
                center: location.coordinate,
                region: Self.region(centeredAt: location.coordinate),
                origin: .current(location.name),
                fitResults: true,
                fallbackMessage: nil
            )
        } catch is CancellationError {
            isLoading = false
        } catch {
            await searchSavedLocation()
        }
    }

    func searchSavedLocation() async {
        let location = savedLocation()
        await search(
            center: location.coordinate,
            region: Self.region(centeredAt: location.coordinate),
            origin: .saved(location.name),
            fitResults: true,
            fallbackMessage: String(
                format: L10n.string("Showing mosques near %@ using your saved prayer location."),
                location.name
            )
        )
    }

    func chooseArea(_ location: PrayerLocation) async {
        await search(
            center: location.coordinate,
            region: Self.region(centeredAt: location.coordinate),
            origin: .chosen(location.name),
            fitResults: true,
            fallbackMessage: nil
        )
    }

    func searchVisibleArea(_ region: MKCoordinateRegion) async {
        await search(
            center: region.center,
            region: region,
            origin: .mapArea,
            fitResults: false,
            fallbackMessage: nil
        )
    }

    func retry() async {
        guard let center = lastSearchCenter, let region = lastSearchRegion, let origin = lastOrigin else {
            didStart = false
            await start()
            return
        }
        await search(
            center: center,
            region: region,
            origin: origin,
            fitResults: true,
            fallbackMessage: fallbackMessage
        )
    }

    func cancel() {
        searchID = UUID()
        searchProvider.cancel()
        if isLoading {
            isLoading = false
            didStart = false
        }
    }

    func shouldOfferSearch(in region: MKCoordinateRegion) -> Bool {
        guard didSearch, let searched = lastSearchRegion else { return false }
        let centerDistance = CLLocation(
            latitude: searched.center.latitude,
            longitude: searched.center.longitude
        ).distance(from: CLLocation(latitude: region.center.latitude, longitude: region.center.longitude))
        let latitudeChange = abs(region.span.latitudeDelta - searched.span.latitudeDelta)
            / max(searched.span.latitudeDelta, 0.000_1)
        let longitudeChange = abs(region.span.longitudeDelta - searched.span.longitudeDelta)
            / max(searched.span.longitudeDelta, 0.000_1)
        return centerDistance > 500 || latitudeChange > 0.2 || longitudeChange > 0.2
    }

    func select(_ place: MosquePlace) {
        selectedPlaceID = place.id
    }

    private func search(
        center: CLLocationCoordinate2D,
        region: MKCoordinateRegion,
        origin: MosqueSearchOrigin,
        fitResults: Bool,
        fallbackMessage: String?
    ) async {
        let requestID = UUID()
        searchID = requestID
        searchProvider.cancel()
        isLoading = true
        errorMessage = nil
        permissionPromptVisible = false
        self.origin = origin
        self.fallbackMessage = fallbackMessage
        lastSearchCenter = center
        lastSearchRegion = region
        lastOrigin = origin

        do {
            let results = try await searchProvider.search(near: center, region: region)
            guard !Task.isCancelled, requestID == searchID else { return }
            places = results
            selectedPlaceID = results.first?.id
            didSearch = true
            isLoading = false
            cameraRegion = fitResults ? Self.fittedRegion(center: center, places: results) : region
            cameraRevision += 1
        } catch is CancellationError {
            guard requestID == searchID else { return }
            isLoading = false
        } catch {
            guard !Task.isCancelled, requestID == searchID else { return }
            places = []
            selectedPlaceID = nil
            didSearch = true
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private static func region(centeredAt coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        MKCoordinateRegion(center: coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
    }

    private static func fittedRegion(center: CLLocationCoordinate2D, places: [MosquePlace]) -> MKCoordinateRegion {
        let coordinates = [center] + places.map(\.coordinate)
        guard let minimumLatitude = coordinates.map(\.latitude).min(),
              let maximumLatitude = coordinates.map(\.latitude).max(),
              let minimumLongitude = coordinates.map(\.longitude).min(),
              let maximumLongitude = coordinates.map(\.longitude).max() else {
            return region(centeredAt: center)
        }
        let latitudeDelta = max((maximumLatitude - minimumLatitude) * 1.6, 0.03)
        let longitudeDelta = max((maximumLongitude - minimumLongitude) * 1.6, 0.03)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}

struct DiscoverView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var selection = DiscoverSection.mosques
    @State private var mosqueFinder: MosqueFinderViewModel

    init(container: AppContainer) {
        self.container = container
        _mosqueFinder = State(initialValue: MosqueFinderViewModel(container: container))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Discover")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            Picker("Discover section", selection: $selection) {
                ForEach(DiscoverSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .accessibilityIdentifier("discover.section.picker")

            Group {
                switch selection {
                case .mosques:
                    MosqueFinderView(container: container, viewModel: mosqueFinder)
                case .qibla:
                    QiblaView(container: container)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 8)
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Discover")
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: selection) { _, newValue in
            if newValue == .qibla { mosqueFinder.cancel() }
        }
    }
}

private struct MosqueFinderView: View {
    @Bindable var container: AppContainer
    @Bindable var viewModel: MosqueFinderViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.openURL) private var openURL
    @Environment(\.salahPalette) private var palette
    @State private var cameraPosition: MapCameraPosition
    @State private var visibleRegion: MKCoordinateRegion
    @State private var showingAreaPicker = false
    @State private var showSearchThisArea = false
    @State private var panelExpanded = false
    @State private var suppressNextCameraChange = false

    init(container: AppContainer, viewModel: MosqueFinderViewModel) {
        self.container = container
        self.viewModel = viewModel
        _cameraPosition = State(initialValue: .region(viewModel.cameraRegion))
        _visibleRegion = State(initialValue: viewModel.cameraRegion)
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    map
                    Divider()
                    resultsContent
                        .frame(width: 360)
                        .background(palette.groupedSurface)
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        map
                        MosqueResultsPanel(
                            availableHeight: proxy.size.height,
                            isExpanded: $panelExpanded,
                            requiresMoreHeight: viewModel.places.isEmpty
                        ) {
                            resultsContent
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("discover.mosqueFinder")
        .task { await viewModel.start() }
        .onChange(of: viewModel.cameraRevision) { _, _ in
            suppressNextCameraChange = true
            showSearchThisArea = false
            visibleRegion = viewModel.cameraRegion
            withAnimation(.easeInOut(duration: 0.35)) {
                cameraPosition = .region(viewModel.cameraRegion)
            }
        }
        .sheet(isPresented: $showingAreaPicker) {
            GlobalLocationPickerView(
                container: container,
                showsCurrentLocation: false,
                footerText: "Search is provided by Apple Maps. This choice only changes the Mosque Finder area."
            ) { location in
                showingAreaPicker = false
                Task { await viewModel.chooseArea(location) }
            }
        }
    }

    private var map: some View {
        Map(position: $cameraPosition) {
            if viewModel.authorization == .authorized {
                UserAnnotation()
            }
            ForEach(Array(viewModel.places.enumerated()), id: \.element.id) { index, place in
                Annotation(place.name, coordinate: place.coordinate, anchor: .bottom) {
                    Button {
                        select(place, expandPanel: true)
                    } label: {
                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(
                                viewModel.selectedPlaceID == place.id ? palette.accent : Color.secondary,
                                in: Circle()
                            )
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mosque \(index + 1), \(place.name)")
                    .accessibilityIdentifier("mosque.map.marker.\(index + 1)")
                }
            }
        }
        .mapControls {
            MapCompass()
            if viewModel.authorization == .authorized {
                MapUserLocationButton()
            }
        }
        .overlay(alignment: .top) {
            if showSearchThisArea {
                Button("Search This Area", systemImage: "magnifyingglass") {
                    showSearchThisArea = false
                    Task { await viewModel.searchVisibleArea(visibleRegion) }
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
                .accessibilityIdentifier("mosque.searchThisArea")
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
            if suppressNextCameraChange {
                suppressNextCameraChange = false
            } else {
                showSearchThisArea = viewModel.shouldOfferSearch(in: context.region)
            }
        }
        .accessibilityIdentifier("mosque.map")
    }

    private var resultsContent: some View {
        MosqueResultsContent(
            viewModel: viewModel,
            onSelect: { select($0, expandPanel: false) },
            onDirections: openDirections,
            onChooseArea: { showingAreaPicker = true },
            onOpenSettings: openSettings
        )
    }

    private func select(_ place: MosquePlace, expandPanel: Bool) {
        viewModel.select(place)
        if expandPanel { panelExpanded = true }
        let focusedRegion = MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: 2_500,
            longitudinalMeters: 2_500
        )
        suppressNextCameraChange = true
        withAnimation(.easeInOut(duration: 0.3)) {
            cameraPosition = .region(focusedRegion)
        }
    }

    private func openDirections(_ place: MosquePlace) {
        place.mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct MosqueResultsPanel<Content: View>: View {
    let availableHeight: CGFloat
    @Binding var isExpanded: Bool
    let requiresMoreHeight: Bool
    @ViewBuilder let content: Content
    @GestureState private var dragTranslation: CGFloat = 0

    var body: some View {
        let collapsedHeight = requiresMoreHeight
            ? min(max(availableHeight * 0.56, 280), availableHeight * 0.75)
            : min(max(availableHeight * 0.36, 220), 280)
        let expandedHeight = max(collapsedHeight, availableHeight * 0.62)
        let baseHeight = isExpanded ? expandedHeight : collapsedHeight
        let currentHeight = min(max(baseHeight - dragTranslation, collapsedHeight), expandedHeight)

        VStack(spacing: 0) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 36, height: 5)
                .padding(.vertical, 9)
                .contentShape(Rectangle().inset(by: -12))
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .updating($dragTranslation) { value, state, _ in
                            state = value.translation.height
                        }
                        .onEnded { value in
                            if value.translation.height < -35 { isExpanded = true }
                            if value.translation.height > 35 { isExpanded = false }
                        }
                )
                .accessibilityLabel(isExpanded ? "Collapse mosque results" : "Expand mosque results")
                .accessibilityAddTraits(.isButton)
                .onTapGesture { withAnimation(.snappy) { isExpanded.toggle() } }

            content
        }
        .frame(maxWidth: .infinity)
        .frame(height: currentHeight, alignment: .top)
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 12, y: -3)
        .accessibilityIdentifier("mosque.results.panel")
    }
}

private struct MosqueResultsContent: View {
    @Bindable var viewModel: MosqueFinderViewModel
    let onSelect: (MosquePlace) -> Void
    let onDirections: (MosquePlace) -> Void
    let onChooseArea: () -> Void
    let onOpenSettings: () -> Void
    @Environment(\.salahPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearest Mosques")
                        .font(.headline)
                    if let origin = viewModel.origin {
                        Text(origin.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else if !viewModel.places.isEmpty {
                    Text("\(viewModel.places.count)")
                        .font(.caption.bold())
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.accentSoft, in: Capsule())
                }
            }

            if let fallbackMessage = viewModel.fallbackMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(fallbackMessage, systemImage: "location.slash.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("mosque.location.fallback")
                    HStack {
                        Button("Choose Area", action: onChooseArea)
                            .buttonStyle(.bordered)
                        if viewModel.canOpenSettings {
                            Button("Open Settings", action: onOpenSettings)
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            content
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.permissionPromptVisible {
            VStack(spacing: 10) {
                Image(systemName: "location.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(palette.accent)
                Text("Find mosques near you")
                    .font(.headline)
                Text("Salah uses a one-time location request while the app is open. It never tracks your location in the background.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Find Nearby Mosques") {
                    Task { await viewModel.findNearby() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("mosque.permission.request")
                Button("Choose Area", action: onChooseArea)
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        } else if viewModel.isLoading, viewModel.places.isEmpty {
            ProgressView("Finding nearby mosques…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            compactUnavailable(
                title: "Nearby mosques unavailable",
                message: LocalizedStringKey(errorMessage),
                symbol: "wifi.exclamationmark",
                actionTitle: "Try Again"
            ) {
                Task { await viewModel.retry() }
            }
        } else if viewModel.didSearch, viewModel.places.isEmpty {
            compactUnavailable(
                title: "No mosques found",
                message: "Move the map or choose another area, then search again.",
                symbol: "moon.stars",
                actionTitle: "Choose Area",
                action: onChooseArea
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(viewModel.places.enumerated()), id: \.element.id) { index, place in
                            MosqueResultRow(
                                place: place,
                                number: index + 1,
                                isSelected: viewModel.selectedPlaceID == place.id,
                                onSelect: { onSelect(place) },
                                onDirections: { onDirections(place) }
                            )
                            .id(place.id)
                        }
                    }
                }
                .onChange(of: viewModel.selectedPlaceID) { _, selection in
                    guard let selection else { return }
                    withAnimation { proxy.scrollTo(selection, anchor: .center) }
                }
            }
        }
    }

    private func compactUnavailable(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        symbol: String,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MosqueResultRow: View {
    let place: MosquePlace
    let number: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDirections: () -> Void
    @Environment(\.salahPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onSelect) {
                HStack(spacing: 10) {
                    Text("\(number)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(isSelected ? palette.accent : Color.secondary, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text(place.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(place.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(distanceText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.accent)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(place.name), \(distanceText), \(place.address)")
            .accessibilityIdentifier("mosque.result.\(number)")

            Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill", action: onDirections)
                .labelStyle(.iconOnly)
                .buttonStyle(.bordered)
                .accessibilityLabel("Directions to \(place.name)")
                .accessibilityIdentifier("mosque.directions.\(number)")
        }
        .padding(10)
        .background(isSelected ? palette.accentSoft : Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(isSelected ? palette.accent.opacity(0.45) : .clear, lineWidth: 1)
        }
    }

    private var distanceText: String {
        Measurement(value: place.distance, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road).locale(L10n.locale))
    }
}

private extension PrayerLocation {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
