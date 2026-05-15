import XCTest
import SwiftUI
@testable import AudioWhisper

/// Tests for DashboardHomeView calculations and logic
@MainActor
final class DashboardHomeViewTests: XCTestCase {

    // MARK: - Streak Calculation Tests

    func testStreakWithNoActivity() {
        let activity: [Date: Int] = [:]
        let streak = DashboardHomeView.testableCalculateStreak(from: activity)
        XCTAssertEqual(streak, 0, "Empty activity should have zero streak")
    }

    func testStreakWithTodayOnly() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let activity: [Date: Int] = [today: 100]

        let streak = DashboardHomeView.testableCalculateStreak(from: activity)
        XCTAssertEqual(streak, 1, "Activity only today should have streak of 1")
    }

    func testStreakWithConsecutiveDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var activity: [Date: Int] = [:]
        for dayOffset in 0..<5 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) {
                activity[date] = 100
            }
        }

        let streak = DashboardHomeView.testableCalculateStreak(from: activity)
        XCTAssertEqual(streak, 5, "5 consecutive days should have streak of 5")
    }

    func testStreakBreaksOnGap() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var activity: [Date: Int] = [:]
        // Today and yesterday have activity
        activity[today] = 100
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            activity[yesterday] = 50
        }
        // Day before yesterday is missing (gap)
        // 3 days ago has activity
        if let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today) {
            activity[threeDaysAgo] = 75
        }

        let streak = DashboardHomeView.testableCalculateStreak(from: activity)
        XCTAssertEqual(streak, 2, "Streak should be 2 due to gap on day before yesterday")
    }

    func testStreakWithZeroWordsDayBreaks() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var activity: [Date: Int] = [:]
        activity[today] = 100
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            activity[yesterday] = 0  // Zero words breaks streak
        }

        let streak = DashboardHomeView.testableCalculateStreak(from: activity)
        XCTAssertEqual(streak, 1, "Zero word day should break streak")
    }

    // MARK: - Active Days Calculation Tests

    func testActiveDaysWithNoActivity() {
        let activity: [Date: Int] = [:]
        let activeDays = DashboardHomeView.testableCalculateActiveDays(from: activity)
        XCTAssertEqual(activeDays, 0)
    }

    func testActiveDaysCountsNonZeroDays() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var activity: [Date: Int] = [:]
        activity[today] = 100
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            activity[yesterday] = 50
        }
        if let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today) {
            activity[twoDaysAgo] = 0  // Should not count
        }
        if let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: today) {
            activity[threeDaysAgo] = 25
        }

        let activeDays = DashboardHomeView.testableCalculateActiveDays(from: activity)
        XCTAssertEqual(activeDays, 3, "Should count only non-zero days")
    }

    // MARK: - Provider Stats Tests

    func testProviderStatsAggregation() {
        let records = [
            makeTestRecord(provider: "local", wordCount: 100),
            makeTestRecord(provider: "local", wordCount: 50),
            makeTestRecord(provider: "parakeet", wordCount: 200)
        ]

        let stats = DashboardHomeView.testableCalculateProviderStats(from: records)

        XCTAssertEqual(stats.count, 2, "Should have 2 providers")

        // Check sorting (highest first)
        XCTAssertEqual(stats[0].provider, "parakeet", "Parakeet should be first with 200 words")
        XCTAssertEqual(stats[0].words, 200)

        XCTAssertEqual(stats[1].provider, "local", "Local should be second with 150 words")
        XCTAssertEqual(stats[1].words, 150)
    }

    func testProviderStatsIconMapping() {
        let records = [
            makeTestRecord(provider: "local", wordCount: 100),
            makeTestRecord(provider: "parakeet", wordCount: 100)
        ]

        let stats = DashboardHomeView.testableCalculateProviderStats(from: records)
        let iconsByProvider = Dictionary(uniqueKeysWithValues: stats.map { ($0.provider, $0.icon) })

        XCTAssertEqual(iconsByProvider["local"], "laptopcomputer")
        XCTAssertEqual(iconsByProvider["parakeet"], "bird")
    }

    func testProviderStatsEmptyRecords() {
        let stats = DashboardHomeView.testableCalculateProviderStats(from: [])
        XCTAssertTrue(stats.isEmpty, "Empty records should produce empty stats")
    }

    // MARK: - Duration Formatting Tests

    func testFormatDurationZero() {
        let result = DashboardHomeView.testableFormatDuration(0)
        XCTAssertEqual(result, "0m")
    }

    func testFormatDurationMinutesOnly() {
        let result = DashboardHomeView.testableFormatDuration(1800) // 30 minutes
        XCTAssertEqual(result, "30m")
    }

    func testFormatDurationHoursAndMinutes() {
        let result = DashboardHomeView.testableFormatDuration(5400) // 1.5 hours
        XCTAssertEqual(result, "1h 30m")
    }

    func testFormatDurationMultipleHours() {
        let result = DashboardHomeView.testableFormatDuration(7200) // 2 hours
        XCTAssertEqual(result, "2h 0m")
    }

    func testFormatDurationNegative() {
        let result = DashboardHomeView.testableFormatDuration(-100)
        XCTAssertEqual(result, "0m", "Negative duration should return 0m")
    }

    // MARK: - View Initialization Tests

    func testViewInitializationWithDefaults() {
        var selectedNav: DashboardNavItem = .dashboard
        let binding = Binding(get: { selectedNav }, set: { selectedNav = $0 })

        // Should not crash with default parameters
        let view = DashboardHomeView(selectedNav: binding)
        XCTAssertNotNil(view)
    }

    func testViewInitializationWithCustomDependencies() {
        var selectedNav: DashboardNavItem = .dashboard
        let binding = Binding(get: { selectedNav }, set: { selectedNav = $0 })
        let mockDataManager = MockDataManager()

        let view = DashboardHomeView(
            selectedNav: binding,
            dataManager: mockDataManager
        )

        XCTAssertNotNil(view)
    }

    // MARK: - Helpers

    private func makeTestRecord(
        provider: String,
        wordCount: Int,
        date: Date = Date()
    ) -> TranscriptionRecord {
        TranscriptionRecord(
            text: String(repeating: "word ", count: wordCount),
            provider: TranscriptionProvider(rawValue: provider) ?? .local,
            duration: 5.0,
            wordCount: wordCount,
            characterCount: wordCount * 5,
            sourceAppBundleId: nil,
            sourceAppName: nil,
            sourceAppIconData: nil
        )
    }
}
