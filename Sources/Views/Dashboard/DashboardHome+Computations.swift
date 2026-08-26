import Foundation
import SwiftUI

// Pure computations behind the Overview page, plus the seams its tests use.
//
// Split out of DashboardHomeView.swift, which had grown past 500 lines. Nothing
// here touches SwiftUI state: every function maps inputs to outputs, which is
// exactly why it is the natural seam and why these are the parts that are
// actually covered by tests.

// MARK: - Pure computations (shared by the view and its tests)
extension DashboardHomeView {
    static func providerIcon(for provider: String) -> String {
        switch provider.lowercased() {
        case "openai":   return "cloud"
        case "gemini":   return "sparkles"
        case "local":    return "laptopcomputer"
        case "parakeet": return "bird"
        default:         return "waveform"
        }
    }

    static func computeProviderStats(
        from records: [TranscriptionRecord]
    ) -> [ProviderStat] {
        var stats: [String: Int] = [:]
        for record in records { stats[record.provider, default: 0] += record.wordCount }
        return providerStats(from: stats)
    }

    /// Builds the sorted stat rows from already-accumulated per-provider word
    /// counts, so a paged scan can accumulate without materialising the records
    /// (audit item B1/G2).
    static func providerStats(from wordsByProvider: [String: Int]) -> [ProviderStat] {
        wordsByProvider
            .map { ProviderStat(provider: $0.key, words: $0.value, icon: providerIcon(for: $0.key)) }
            .sorted { $0.words > $1.words }
    }

    static func mergeDailyActivity(
        base: [Date: Int],
        records: [TranscriptionRecord]
    ) -> [Date: Int] {
        let calendar = Calendar.current
        var dailyWords: [Date: Int] = [:]
        for record in records {
            dailyWords[calendar.startOfDay(for: record.date), default: 0] += record.wordCount
        }
        return mergeDailyActivity(base: base, dailyWords: dailyWords)
    }

    /// Fills gaps in `base` from per-day word counts a paged scan accumulated
    /// (audit item B1/G2). A day already present and non-zero in `base` wins —
    /// the store's own figure is authoritative; records only backfill days it
    /// has no number for.
    static func mergeDailyActivity(
        base: [Date: Int],
        dailyWords: [Date: Int]
    ) -> [Date: Int] {
        var activity = base
        for (day, words) in dailyWords where activity[day] == nil || activity[day] == 0 {
            activity[day, default: 0] += words
        }
        return activity
    }

    /// Consecutive days (ending today) with non-zero word counts.
    static func computeStreak(from activity: [Date: Int]) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var currentDate = Date()
        while true {
            let day = calendar.startOfDay(for: currentDate)
            if let words = activity[day], words > 0 {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: currentDate) else { break }
                currentDate = prev
            } else { break }
        }
        return streak
    }

    static func computeActiveDays(from activity: [Date: Int]) -> Int {
        activity.filter { $0.value > 0 }.count
    }

    static func numberString(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func durationString(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" } else { return "\(minutes)m" }
    }
}

// MARK: - Testable Helpers
extension DashboardHomeView {
    static func testableCalculateStreak(from activity: [Date: Int]) -> Int {
        computeStreak(from: activity)
    }

    static func testableCalculateActiveDays(from activity: [Date: Int]) -> Int {
        computeActiveDays(from: activity)
    }

    static func testableCalculateProviderStats(
        from records: [TranscriptionRecord]
    ) -> [ProviderStat] {
        computeProviderStats(from: records)
    }

    static func testableFormatDuration(_ interval: TimeInterval) -> String {
        durationString(interval)
    }
}

#Preview("Dashboard Home") {
    DashboardHomeView(selectedNav: .constant(.dashboard))
        .frame(width: 900, height: 700)
}
