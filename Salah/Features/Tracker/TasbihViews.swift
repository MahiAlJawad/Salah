import AVFoundation
import SwiftUI
import UIKit

struct TasbihCounterPad: View {
    @Binding var count: Int
    @Binding var goal: Int
    let onIncrement: () -> Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.salahPalette) private var palette
    @State private var resetArmed = false
    @State private var rippleExpanded = true
    @State private var showingCustomGoal = false
    @State private var customGoalText = ""
    @State private var showingGoalCompletion = false
    @State private var completedGoal = 0

    private let presetGoals = [33, 99, 100]

    private var goalProgress: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(count) / Double(goal))
    }

    private var customGoalValue: Int? {
        guard let value = Int(customGoalText), (1...999_999).contains(value) else { return nil }
        return value
    }

    var body: some View {
        GeometryReader { proxy in
            let contentHeight = min(proxy.size.height, 752)
            let contentTop = max(0, (proxy.size.height - contentHeight) / 2)
            let ringSize = min(460, max(280, min(proxy.size.width * 0.92, contentHeight * 0.62)))
            let countSize = min(136, max(80, proxy.size.width * 0.30))
            let handWidth = min(148, max(100, proxy.size.width * 0.25))
            let handHeight = handWidth * 86 / 72
            let ringCenterY = contentTop + contentHeight * 0.39
            let hintSpacing = min(88, max(52, contentHeight * 0.09))
            let hintHeight = handHeight + 42
            let preferredHintTop = ringCenterY + ringSize * 0.27 + hintSpacing
            let hintTop = min(preferredHintTop, proxy.size.height - hintHeight - 24)

            ZStack(alignment: .topTrailing) {
                Button(action: increment) {
                    ZStack {
                        padBackground

                        Circle()
                            .stroke(palette.accent.opacity(rippleExpanded ? 0 : 0.45), lineWidth: 2)
                            .frame(width: 96, height: 96)
                            .scaleEffect(rippleExpanded ? 1.7 : 0.35)
                            .position(x: proxy.size.width / 2, y: ringCenterY)

                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        stops: [
                                            .init(color: palette.groupedSurface.opacity(colorScheme == .dark ? 0.52 : 0.96), location: 0),
                                            .init(color: palette.groupedSurface.opacity(colorScheme == .dark ? 0.52 : 0.96), location: 0.27),
                                            .init(color: palette.groupedSurface.opacity(colorScheme == .dark ? 0.28 : 0.48), location: 0.29),
                                            .init(color: palette.groupedSurface.opacity(colorScheme == .dark ? 0.18 : 0.34), location: 0.54),
                                            .init(color: .clear, location: 0.56),
                                            .init(color: .clear, location: 0.73),
                                            .init(color: palette.groupedSurface.opacity(colorScheme == .dark ? 0.18 : 0.34), location: 0.75),
                                            .init(color: palette.groupedSurface.opacity(colorScheme == .dark ? 0.12 : 0.24), location: 0.98),
                                            .init(color: .clear, location: 1)
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: ringSize / 2
                                    )
                                )
                                .frame(width: ringSize, height: ringSize)

                            if goal > 0 {
                                Circle()
                                    .trim(from: 0, to: goalProgress)
                                    .stroke(
                                        palette.accent,
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                    )
                                    .frame(width: ringSize * 0.72, height: ringSize * 0.72)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.snappy, value: goalProgress)
                            }

                            VStack(spacing: 8) {
                                Text(count, format: .number)
                                    .font(.system(size: countSize, weight: .semibold, design: .rounded).monospacedDigit())
                                    .tracking(-3)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.45)
                                Text("count")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                                if goal > 0 {
                                    Text("\(count) of \(goal)")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(palette.accentForeground)
                                }
                            }
                            .padding(.horizontal, 22)
                        }
                        .position(x: proxy.size.width / 2, y: ringCenterY)

                        VStack(spacing: 13) {
                            TasbihHandHint(color: palette.accent)
                                .frame(width: handWidth, height: handHeight)

                            Text("Tap anywhere to count")
                                .font(.system(size: min(21, max(16, proxy.size.width * 0.045)), weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(height: hintHeight, alignment: .top)
                        .position(x: proxy.size.width / 2, y: hintTop + hintHeight / 2)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                }
                .buttonStyle(TasbihPadButtonStyle())
                .accessibilityLabel("Tasbih counter. Current count \(count).")
                .accessibilityHint("Tap anywhere to increase the count")
                .accessibilityIdentifier("tasbih.counter")

                VStack {
                    HStack(alignment: .top) {
                        goalMenu
                        Spacer(minLength: 12)
                        resetButton
                    }
                    Spacer()
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Tasbih goal completed", isPresented: $showingGoalCompletion) {
            Button("OK") {
                count = 0
            }
        } message: {
            Text("You completed \(completedGoal) counts.")
        }
    }

    private var padBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.groupedSurface,
                            palette.accentSoft.opacity(colorScheme == .dark ? 0.76 : 0.94)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            palette.groupedSurface.opacity(colorScheme == .dark ? 0.54 : 0.92),
                            palette.accent.opacity(colorScheme == .dark ? 0.07 : 0.04),
                            .clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.39),
                        startRadius: 4,
                        endRadius: 230
                    )
                )

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [palette.accent.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 170
                    )
                )
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .offset(y: 230)
        }
    }

    private var resetButton: some View {
        Button(action: handleReset) {
            Label(L10n.dynamic(resetArmed ? "Tap again" : "Reset"), systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .foregroundStyle(resetArmed ? Color.red : palette.accentForeground)
                .background(resetArmed ? Color.red.opacity(0.13) : palette.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.dynamic(resetArmed ? "Confirm reset counter" : "Reset counter"))
        .accessibilityIdentifier("tasbih.reset")
        .animation(.easeInOut(duration: 0.18), value: resetArmed)
    }

    private var goalMenu: some View {
        Menu {
            Button {
                selectGoal(0)
            } label: {
                if goal == 0 {
                    Label("No Goal", systemImage: "checkmark")
                } else {
                    Text("No Goal")
                }
            }

            ForEach(presetGoals, id: \.self) { preset in
                Button {
                    selectGoal(preset)
                } label: {
                    if goal == preset {
                        Label("\(preset)", systemImage: "checkmark")
                    } else {
                        Text("\(preset)")
                    }
                }
            }

            Divider()

            Button {
                customGoalText = goal > 0 ? String(goal) : ""
                showingCustomGoal = true
            } label: {
                Label("Custom…", systemImage: "number")
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "target")
                Text(goal > 0 ? L10n.string("Goal: \(goal)") : L10n.string("Set Goal"))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .foregroundStyle(palette.accentForeground)
            .background(palette.accentSoft, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(goal > 0 ? L10n.string("Tasbih goal, \(goal)") : L10n.string("Tasbih goal, none"))
        .accessibilityIdentifier("tasbih.goal.menu")
        .alert("Custom Tasbih Goal", isPresented: $showingCustomGoal) {
            TextField("Goal count", text: $customGoalText)
                .keyboardType(.numberPad)
            Button("Set Goal") {
                if let customGoalValue {
                    selectGoal(customGoalValue)
                }
            }
            .disabled(customGoalValue == nil)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Enter a goal from 1 to 999,999.")
        }
    }

    private func increment() {
        guard let nextCount = onIncrement() else { return }
        count = nextCount

        if goal > 0, nextCount == goal {
            completedGoal = goal
            TasbihCompletionFeedback.shared.play()
            showingGoalCompletion = true
        } else {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        guard !reduceMotion else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            rippleExpanded = false
        }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.52)) {
                rippleExpanded = true
            }
        }
    }

    private func handleReset() {
        guard resetArmed else {
            resetArmed = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                resetArmed = false
            }
            return
        }

        count = 0
        resetArmed = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func selectGoal(_ newGoal: Int) {
        goal = newGoal
        if newGoal > 0, count >= newGoal {
            count = 0
        }
    }
}

struct TasbihPadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.015 : 0)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TasbihHandHint: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let scale = proxy.size.width / 72
            let fingertip = CGPoint(
                x: proxy.size.width * 34.5 / 72,
                y: proxy.size.height * 14 / 86
            )

            ZStack {
                Circle()
                    .stroke(color.opacity(0.22), lineWidth: 3 * scale)
                    .frame(width: 34 * scale, height: 34 * scale)
                    .position(fingertip)

                Circle()
                    .stroke(color.opacity(0.45), lineWidth: 3 * scale)
                    .frame(width: 20 * scale, height: 20 * scale)
                    .position(fingertip)

                TasbihFingerShape()
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: 3 * scale,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

struct TasbihFingerShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width / 72, y: rect.minY + y * rect.height / 86)
        }

        var path = Path()
        path.move(to: point(34.5, 14))
        path.addLine(to: point(34.5, 48))

        path.move(to: point(34.5, 48))
        path.addLine(to: point(34.5, 31.5))
        path.addCurve(
            to: point(39.5, 26),
            control1: point(34.5, 28.5),
            control2: point(36.5, 26)
        )
        path.addCurve(
            to: point(44.5, 31.4),
            control1: point(42.5, 26),
            control2: point(44.5, 28.4)
        )
        path.addLine(to: point(44.5, 45.5))
        path.addLine(to: point(44.5, 36.9))
        path.addCurve(
            to: point(49.5, 31.6),
            control1: point(44.5, 33.9),
            control2: point(46.5, 31.6)
        )
        path.addCurve(
            to: point(54.5, 37),
            control1: point(52.5, 31.6),
            control2: point(54.5, 34)
        )
        path.addLine(to: point(54.5, 47.6))
        path.addLine(to: point(54.5, 42.3))
        path.addCurve(
            to: point(59.5, 37.1),
            control1: point(54.5, 39.4),
            control2: point(56.6, 37.1)
        )
        path.addCurve(
            to: point(64.5, 42.3),
            control1: point(62.4, 37.1),
            control2: point(64.5, 39.4)
        )
        path.addLine(to: point(64.5, 56.2))
        path.addCurve(
            to: point(39.5, 82),
            control1: point(64.5, 71.7),
            control2: point(54, 82)
        )
        path.addLine(to: point(35.8, 82))
        path.addCurve(
            to: point(17.7, 71.4),
            control1: point(27.2, 82),
            control2: point(21.8, 77.4)
        )
        path.addLine(to: point(2.8, 54.7))
        path.addCurve(
            to: point(4.9, 46.9),
            control1: point(1.1, 52),
            control2: point(2.1, 48.4)
        )
        path.addCurve(
            to: point(12, 48.4),
            control1: point(7.3, 45.6),
            control2: point(10.3, 46.2)
        )
        path.addLine(to: point(19.5, 58.1))
        path.addLine(to: point(19.5, 14))
        path.addCurve(
            to: point(27, 6.5),
            control1: point(19.5, 9.8),
            control2: point(22.8, 6.5)
        )
        path.addCurve(
            to: point(34.5, 14),
            control1: point(31.2, 6.5),
            control2: point(34.5, 9.8)
        )
        path.closeSubpath()
        return path
    }
}

@MainActor
final class TasbihCompletionFeedback {
    static let shared = TasbihCompletionFeedback()

    private var player: AVAudioPlayer?

    private init() { }

    func play() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        player = try? AVAudioPlayer(data: Self.completionChime)
        player?.volume = 0.45
        player?.prepareToPlay()
        player?.play()
    }

    private static let completionChime: Data = {
        let sampleRate: UInt32 = 44_100
        let duration = 0.52
        let sampleCount = Int(Double(sampleRate) * duration)
        let dataSize = UInt32(sampleCount * MemoryLayout<Int16>.size)
        var data = Data()

        func appendString(_ value: String) {
            data.append(contentsOf: value.utf8)
        }

        func appendInteger<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { bytes in
                data.append(contentsOf: bytes)
            }
        }

        appendString("RIFF")
        appendInteger(UInt32(36) + dataSize)
        appendString("WAVE")
        appendString("fmt ")
        appendInteger(UInt32(16))
        appendInteger(UInt16(1))
        appendInteger(UInt16(1))
        appendInteger(sampleRate)
        appendInteger(sampleRate * 2)
        appendInteger(UInt16(2))
        appendInteger(UInt16(16))
        appendString("data")
        appendInteger(dataSize)

        for sampleIndex in 0..<sampleCount {
            let time = Double(sampleIndex) / Double(sampleRate)
            let firstEnvelope = sineEnvelope(time, start: 0, end: 0.30)
            let secondEnvelope = sineEnvelope(time, start: 0.16, end: duration)
            let firstTone = sin(2 * Double.pi * 659.25 * time) * firstEnvelope
            let secondTone = sin(2 * Double.pi * 880.00 * time) * secondEnvelope
            let amplitude = (firstTone + secondTone) * 0.17
            appendInteger(Int16(clamping: Int(amplitude * Double(Int16.max))))
        }

        return data
    }()

    private static func sineEnvelope(_ time: Double, start: Double, end: Double) -> Double {
        guard time >= start, time <= end else { return 0 }
        let progress = (time - start) / (end - start)
        return sin(Double.pi * progress)
    }
}

struct TasbihTotalEditor: View {
    let day: LocalDay
    let timeZone: TimeZone
    let onSave: (Int) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var countText: String
    @State private var errorMessage: String?

    init(day: LocalDay, timeZone: TimeZone, count: Int, onSave: @escaping (Int) throws -> Void) {
        self.day = day
        self.timeZone = timeZone
        self.onSave = onSave
        _countText = State(initialValue: count.formatted(.number.grouping(.never).locale(L10n.locale)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(PrayerDateFormatting.fullDate(day, timeZone: timeZone), systemImage: "calendar")
                }
                Section {
                    TextField("Total for this day", text: $countText)
                        .keyboardType(.numberPad)
                        .font(.title2.monospacedDigit())
                        .accessibilityIdentifier("calendar.tasbih-input")
                } header: {
                    Text("Total for this day")
                } footer: {
                    Text("This replaces the saved total for this day.")
                }
                if TasbihTotalInput.parse(countText) == nil {
                    Text("Enter a valid nonnegative whole number.").foregroundStyle(.secondary)
                }
                if let errorMessage { Text(L10n.dynamic(errorMessage)).foregroundStyle(.red) }
            }
            .navigationTitle("Edit Tasbih")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let count = TasbihTotalInput.parse(countText) else { return }
                        do {
                            try onSave(count)
                            dismiss()
                        } catch {
                            errorMessage = "Your change could not be saved."
                        }
                    }.disabled(TasbihTotalInput.parse(countText) == nil)
                }
            }
        }
    }
}
