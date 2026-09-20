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

private struct QiblaBeam: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.43
        let halfWidth = 7.0 * Double.pi / 180

        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(
            x: center.x + cos(-Double.pi / 2 - halfWidth) * radius,
            y: center.y + sin(-Double.pi / 2 - halfWidth) * radius
        ))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .radians(-Double.pi / 2 - halfWidth),
            endAngle: .radians(-Double.pi / 2 + halfWidth),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct CompassDial: View {
    let heading: Double

    var body: some View {
        ZStack {
            ForEach(0..<72, id: \.self) { index in
                let isMajor = index.isMultiple(of: 18)
                let isMedium = index.isMultiple(of: 9)
                Capsule()
                    .fill(Color.secondary.opacity(isMajor ? 0.9 : isMedium ? 0.7 : 0.42))
                    .frame(width: isMajor ? 3 : 1.5, height: isMajor ? 15 : isMedium ? 11 : 7)
                    .offset(y: -116)
                    .rotationEffect(.degrees(Double(index) * 5))
            }

            Text("N").offset(y: -88)
            Text("S").offset(y: 88)
            Text("W").offset(x: -88)
            Text("E").offset(x: 88)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.headline)
        .foregroundStyle(.secondary)
        .rotationEffect(.degrees(-heading))
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

    private var turnDegrees: Int {
        Int(abs(relativeBearing).rounded())
    }

    private var alignmentTitle: String {
        guard headingProvider.heading != nil else { return L10n.string("Waiting for heading") }
        if isAligned { return L10n.string("Facing Qibla") }
        let key: String.LocalizationValue = relativeBearing < 0 ? "Turn %lld° left" : "Turn %lld° right"
        return String(format: L10n.string(key), Int64(turnDegrees))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if headingProvider.isAvailable {
                    compass
                    VStack(spacing: 4) {
                        Text(alignmentTitle)
                            .font(.title3.bold())
                            .foregroundStyle(isAligned ? palette.accent : Color.primary)
                            .contentTransition(.numericText())
                        if !isAligned {
                            Text("Align the blue arc with the top gate")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .multilineTextAlignment(.center)
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
                .stroke(Color(uiColor: .separator).opacity(0.25), lineWidth: 18)
                .padding(9)

            CompassDial(heading: headingProvider.heading ?? 0)
                .animation(.smooth(duration: 0.45), value: headingProvider.heading)

            QiblaBeam()
                .fill(
                    RadialGradient(
                        colors: [palette.accent.opacity(0.04), palette.accent.opacity(0.16)],
                        center: .center,
                        startRadius: 16,
                        endRadius: 118
                    )
                )
                .rotationEffect(.degrees(relativeBearing))
                .animation(.smooth(duration: 0.45), value: relativeBearing)

            Circle()
                .trim(from: 0, to: 0.07)
                .stroke(palette.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .padding(10)
                .rotationEffect(.degrees(relativeBearing - 102.6))
                .animation(.smooth(duration: 0.45), value: relativeBearing)

            VStack {
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 7, height: 24)
                    .shadow(color: palette.accent.opacity(isAligned ? 0.5 : 0), radius: 7)
                Spacer()
            }
            .padding(.top, 2)

            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 32, height: 32)
                .overlay {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 18, height: 18)
                }

            if isAligned {
                Circle()
                    .stroke(palette.accent.opacity(0.18), lineWidth: 10)
                    .padding(4)
                    .transition(.opacity)
            }
        }
        .frame(width: 270, height: 270)
        .animation(.easeInOut(duration: 0.2), value: isAligned)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Qibla compass")
        .accessibilityValue(alignmentTitle)
        .accessibilityHint(isAligned ? "" : "Align the blue arc with the top gate")
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
