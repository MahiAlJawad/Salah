import SwiftUI

struct AboutView: View {
    @Environment(\.salahPalette) private var palette

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "moon.stars.fill").font(.system(size: 52)).foregroundStyle(palette.accent)
                    Text("Salah").font(.title.bold())
                    Text("Prayer times and daily worship tracking.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical)
            }
            Section {
                LabeledContent("Version", value: appVersion)
            }
            Section("Prayer-Time Notice") {
                Text("Prayer timings can vary by calculation method, madhab, adjustments, local conditions, and local authority. Salah is not an official religious authority. Confirm timings with an appropriate local authority when necessary.")
            }
        }
        .navigationTitle("About Salah")
        .navigationBarTitleDisplayMode(.inline)
        .phoneOnlyHideTabBar()
    }
}
