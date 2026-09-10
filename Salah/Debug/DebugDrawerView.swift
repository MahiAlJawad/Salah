//
//  DebugDrawerView.swift
//  Salah
//
//  Created by Kazi Tanjim Shakib on 31/7/26.
//

import Foundation
import SwiftUI

// MARK: - Debug Drawer (DEBUG builds only)

#if DEBUG
@MainActor
struct DebugDrawerView: View {
    @Bindable var container: AppContainer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.salahPalette) private var palette

    // Lightweight live-state values remain in AppStorage; histories use SwiftData.
    @AppStorage("salah.deeds.istighfar-count") private var tasbihCount = 0
    @AppStorage("salah.deeds.tasbih-goal") private var tasbihGoal = 0
    @AppStorage("salah.deeds.tasbih-day") private var tasbihDay = ""
    @AppStorage("salah.deeds.good-deeds-mask") private var goodDeedsMask = 0
    @AppStorage("salah.deeds.good-deeds-day")  private var goodDeedsDay = ""
    @AppStorage("salah.deeds.charity-total")   private var charityTotal = 0
    @AppStorage("salah.deeds.charity-goal")    private var charityGoal = 100
    @AppStorage("salah.deeds.charity-month")   private var charityMonth = ""

    @State private var seedMessage: String?
    @State private var deleteMessage: String?
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "Debug tools are only compiled in DEBUG builds and are never present in App Store releases.",
                        systemImage: "hammer.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                Section("Tracker Tab") {
                    Button {
                        seedDummyData()
                    } label: {
                        Label("Add 30 Days of Dummy Data", systemImage: "wand.and.stars")
                    }
                    .foregroundStyle(palette.accent)

                    if let seedMessage {
                        Label(seedMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                }

                Section("Reset") {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete All Dummy Data", systemImage: "trash.fill")
                    }

                    if let deleteMessage {
                        Label(deleteMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Debug Drawer 🛠️")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Delete All Dummy Data?",
                isPresented: $showingDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    deleteDummyData()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This resets all Tracker tab data: prayer records, Tasbih counter, Good Deeds, and Charity.")
            }
        }
    }

    // MARK: Seed logic

    private func seedDummyData() {
        let timeZone = container.settings.location.timeZone
        let today = LocalDay(.now, timeZone: timeZone)
        try? container.trackerHistoryRepository.clearAll()

        // ── Salah: 30 past days, 3–5 random prayers completed each day ──
        let prayers = PrayerType.allCases
        for offset in 1...30 {
            let day = today.adding(days: -offset, in: timeZone)
            let doneCount = Int.random(in: 3...5)
            let shuffled = prayers.shuffled().prefix(doneCount)
            for prayer in shuffled {
                try? container.trackingRepository.setCompleted(
                    true, prayer: prayer,
                    day: day, timeZone: timeZone,
                    source: "debug"
                )
            }
        }

        // ── Tasbih: seed daily totals and keep today's live counter in sync ──
        tasbihCount = Int.random(in: 40...99)
        tasbihGoal = 100
        tasbihDay = today.key
        for offset in 0..<30 {
            let day = today.adding(days: -offset, in: timeZone)
            let count = offset == 0 ? tasbihCount : Int.random(in: 0...180)
            try? container.trackerHistoryRepository.setTasbihCount(count, goal: 100, on: day)
        }

        // ── Nafl: seed 30 days and mark all five items for today ──
        goodDeedsDay = today.key
        goodDeedsMask = 0b1_1111
        for offset in 0..<30 {
            let day = today.adding(days: -offset, in: timeZone)
            let mask = offset == 0 ? goodDeedsMask : Int.random(in: 0...0b1_1111)
            try? container.trackerHistoryRepository.setNaflCompletedMask(mask, on: day)
        }

        // ── Charity: plausible amount for the current month ──
        let components = Calendar.current.dateComponents([.year, .month], from: .now)
        charityMonth = String(format: "%04d-%02d", components.year ?? 1970, components.month ?? 1)
        charityGoal = 100
        let amounts = [15, 20, 25]
        let entries = amounts.enumerated().map { index, amount in
            CharityEntry(
                amount: Double(amount),
                date: Calendar.current.date(byAdding: .day, value: -(index * 4), to: .now) ?? .now,
                category: CharityCategory.allCases[index],
                recipient: ["Local food bank", "Education fund", "Emergency appeal"][index]
            )
        }
        for entry in entries {
            try? container.trackerHistoryRepository.addCharityEntry(entry)
        }
        charityTotal = amounts.reduce(0, +)

        seedMessage = "Dummy data seeded for all Deeds sections ✓"
        deleteMessage = nil   // clear any prior delete confirmation
    }

    // MARK: Delete logic

    private func deleteDummyData() {
        // ── Prayer records: wipe all SwiftData tracker records ──
        try? container.trackingRepository.clearAll()

        // ── Tasbih ──
        tasbihCount = 0
        tasbihGoal = 0
        tasbihDay = ""

        // ── Good Deeds ──
        goodDeedsMask = 0
        goodDeedsDay = ""

        // ── Charity ──
        charityTotal = 0
        charityGoal = 100
        charityMonth = ""
        try? container.trackerHistoryRepository.clearAll()

        deleteMessage = "All dummy data deleted ✓"
        seedMessage = nil   // clear any prior seed confirmation
    }
}
#endif
