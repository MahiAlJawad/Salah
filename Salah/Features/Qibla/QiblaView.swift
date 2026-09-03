@preconcurrency import CoreLocation
import SwiftUI
import UIKit

@MainActor
@Observable
final class QiblaHeadingProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var heading: Double?
    private(set) var accuracy: Double?
    private(set) var isAvailable = CLLocationManager.headingAvailable()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 1
    }

    func start() {
        isAvailable = CLLocationManager.headingAvailable()
        guard isAvailable else { return }
        manager.startUpdatingHeading()
    }

    func stop() {
        manager.stopUpdatingHeading()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        accuracy = newHeading.headingAccuracy
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        (accuracy ?? 0) > 20
    }
}

enum QiblaGeometry {
    static let kaaba = CLLocationCoordinate2D(latitude: 21.4225, longitude: 39.8262)

    static func bearing(from location: PrayerLocation) -> Double {
        let latitude = location.latitude * .pi / 180
        let longitude = location.longitude * .pi / 180
        let destinationLatitude = kaaba.latitude * .pi / 180
        let destinationLongitude = kaaba.longitude * .pi / 180
        let delta = destinationLongitude - longitude
        let bearingYComponent = sin(delta) * cos(destinationLatitude)
        let bearingXComponent = cos(latitude) * sin(destinationLatitude) - sin(latitude) * cos(destinationLatitude) * cos(delta)
        return normalized(atan2(bearingYComponent, bearingXComponent) * 180 / .pi)
    }

    static func distance(from location: PrayerLocation) -> Measurement<UnitLength> {
        let origin = CLLocation(latitude: location.latitude, longitude: location.longitude)
        let destination = CLLocation(latitude: kaaba.latitude, longitude: kaaba.longitude)
        return Measurement(value: origin.distance(from: destination), unit: .meters).converted(to: .kilometers)
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    static func shortestAngle(_ degrees: Double) -> Double {
        let value = normalized(degrees)
        return value > 180 ? value - 360 : value
    }
}

struct QiblaView: View {
    @Bindable var container: AppContainer
    @Environment(\.salahPalette) private var palette
    @State private var headingProvider = QiblaHeadingProvider()

    private var qiblaBearing: Double {
        QiblaGeometry.bearing(from: container.settings.location)
    }

    private var relativeBearing: Double {
        QiblaGeometry.shortestAngle(qiblaBearing - (headingProvider.heading ?? 0))
    }

    private var isAligned: Bool {
        headingProvider.heading != nil && abs(relativeBearing) < 6
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("Qibla")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                Label(container.localizedLocationName, systemImage: "location.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if headingProvider.isAvailable {
                    compass
                    Label(
                        isAligned ? "Aligned — facing the Ka'bah" : "Turn until the marker points up",
                        systemImage: isAligned ? "checkmark.circle.fill" : "location.north.line.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(isAligned ? palette.accent : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                } else {
                    ContentUnavailableView {
                        Label("Compass Unavailable", systemImage: "location.slash")
                    } description: {
                        Text("This device does not provide live heading updates. The calculated Qibla bearing is still shown below.")
                    }
                    .frame(minHeight: 260)
                }

                HStack(spacing: 12) {
                    qiblaMetric("Heading", value: headingProvider.heading.map { "\(Int($0.rounded()).formatted(.number.locale(L10n.locale)))°" } ?? "—")
                    qiblaMetric("Qibla", value: "\(Int(qiblaBearing.rounded()).formatted(.number.locale(L10n.locale)))°")
                    qiblaMetric("To Makkah", value: QiblaGeometry.distance(from: container.settings.location).formatted(.measurement(width: .abbreviated, usage: .road).locale(L10n.locale)))
                }

                SalahCard {
                    Label("Compass guidance", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        .font(.headline)
                    Text("Hold the iPhone flat and turn slowly. Move away from metal, magnets, and electronic equipment if the heading drifts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let accuracy = headingProvider.accuracy, accuracy > 20 {
                        Label("Compass accuracy is currently low", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(palette.screenBackground.ignoresSafeArea())
        .navigationTitle("Qibla")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { headingProvider.start() }
        .onDisappear { headingProvider.stop() }
    }

    private var compass: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .secondarySystemBackground))
            Circle()
                .stroke(Color(uiColor: .separator), lineWidth: 1)
            Circle()
                .stroke(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1, dash: [2, 8]))
                .padding(24)

            ZStack {
                Text("N").font(.headline).frame(maxHeight: .infinity, alignment: .top).padding(.top, 18)
                Text("S").font(.headline).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 18)
                Text("W").font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 18)
                Text("E").font(.headline).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 18)
            }
            .rotationEffect(.degrees(-(headingProvider.heading ?? 0)))
            .animation(.smooth(duration: 0.45), value: headingProvider.heading)

            VStack(spacing: 5) {
                Image(systemName: "building.columns.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(palette.accent, in: RoundedRectangle(cornerRadius: 10))
                Image(systemName: "arrowtriangle.up.fill")
                    .foregroundStyle(palette.accent)
                Rectangle()
                    .fill(LinearGradient(colors: [palette.accent, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: 72)
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .rotationEffect(.degrees(relativeBearing))
            .animation(.smooth(duration: 0.45), value: relativeBearing)

            Circle()
                .fill(Color.primary)
                .frame(width: 16, height: 16)
                .overlay {
                    if isAligned {
                        Circle().stroke(palette.accent, lineWidth: 3).frame(width: 52, height: 52)
                    }
                }
        }
        .frame(width: 270, height: 270)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Qibla compass")
        .accessibilityValue(headingProvider.heading == nil ? "Waiting for heading" : "Qibla is \(Int(abs(relativeBearing).rounded())) degrees \(relativeBearing < 0 ? "left" : "right")")
    }

    private func qiblaMetric(_ title: String, value: String) -> some View {
        SalahCard {
            Text(L10n.dynamic(title))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
