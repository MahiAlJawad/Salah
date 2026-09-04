import SwiftUI

struct TrackerPrayerSummary: View {
    let viewModel: TrackerViewModel
    let title: String
    @Environment(\.salahPalette) private var palette

    var body: some View {
        SalahCard(isTransparent: true) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold())
                    Text("Private and stored on this device")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                Spacer()
                Text("\(viewModel.completedCount)/5")
                    .font(.largeTitle.bold().monospacedDigit())
            }
            ProgressView(value: viewModel.progress)
                .tint(.white)
                .accessibilityLabel("Daily completion")
                .accessibilityValue("\(viewModel.completedCount) of 5 prayers completed")
        }
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [palette.heroStart, palette.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

struct TrackerPrayerRow: View {
    let prayer: PrayerType
    let viewModel: TrackerViewModel
    let action: () -> Void
    @Environment(\.salahPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            PrayerIcon(prayer: prayer)
            TrackerPrayerStatus(viewModel: viewModel, prayer: prayer, action: action)
        }
        .padding()
        .frame(minHeight: 64)
        .background(palette.groupedSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct TrackerPrayerStatus: View {
    let viewModel: TrackerViewModel
    let prayer: PrayerType
    let action: () -> Void
    @Environment(\.salahPalette) private var palette

    var body: some View {
        let completed = viewModel.completed.contains(prayer)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.dynamic(prayer.title)).font(.headline)
                Text(L10n.dynamic(completed ? "Completed" : "Not marked yet"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: action) {
                Group {
                    if completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(palette.accent)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.title2)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            // Keep the checkmark's original trailing footprint in the card.
            .padding(.horizontal, -10)
            .accessibilityLabel(L10n.string("\(prayer.title), \(completed ? L10n.string("completed") : L10n.string("not completed"))"))
            .accessibilityHint(L10n.dynamic(completed ? "Double tap to mark as not completed" : "Double tap to mark as completed"))
        }
        .frame(maxWidth: .infinity)
    }
}

struct GoodDeedRow: View {
    let title: String
    let symbol: String
    let completed: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TrackerStatusRowContent(
                title: title,
                subtitle: completed ? "Completed" : "Not marked yet",
                completed: completed,
                accent: accent
            ) {
                TrackerSymbolIcon(symbol: symbol)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(title)
        .accessibilityValue(L10n.dynamic(completed ? "completed" : "not completed"))
        .accessibilityHint(L10n.dynamic(completed ? "Double tap to mark as not completed" : "Double tap to mark as completed"))
    }
}

private struct TrackerStatusRowContent<Leading: View>: View {
    let title: String
    let subtitle: String
    let completed: Bool
    let accent: Color
    @ViewBuilder let leading: Leading

    var body: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.dynamic(title)).font(.headline)
                Text(L10n.dynamic(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(completed ? accent : .secondary)
                .accessibilityHidden(true)
        }
    }
}
