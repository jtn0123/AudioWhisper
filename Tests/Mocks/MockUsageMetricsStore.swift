import Foundation
@testable import AudioWhisper

/// Protocol for UsageMetricsStore to enable mocking
@MainActor
protocol UsageMetricsStoreProtocol {
    var snapshot: UsageSnapshot { get }

    func recordSession(duration: TimeInterval?, wordCount: Int, characterCount: Int)
    func getDailyActivity(days: Int) -> [Date: Int]
    func calculateStreak() -> Int
    func rebuild(using records: [TranscriptionRecord])
    func rebuildDailyActivity(using records: [TranscriptionRecord])
    func reset()
    func bootstrapIfNeeded(dataManager: DataManagerProtocol) async
}

/// Mock implementation for testing usage metrics
@MainActor
final class MockUsageMetricsStore: UsageMetricsStoreProtocol {
    // MARK: - State

    var snapshot: UsageSnapshot = .empty

    // MARK: - Configurable Data

    var dailyActivityData: [Date: Int] = [:]
    var streakValue: Int = 0

    // MARK: - Call Tracking

    var recordSessionCallCount = 0
    var recordSessionLastDuration: TimeInterval?
    var recordSessionLastWordCount: Int?
    var recordSessionLastCharacterCount: Int?

    var getDailyActivityCallCount = 0
    var getDailyActivityLastDays: Int?

    var calculateStreakCallCount = 0
    var rebuildCallCount = 0
    var rebuildDailyActivityCallCount = 0
    var resetCallCount = 0
    var bootstrapIfNeededCallCount = 0

    // MARK: - Protocol Methods

    func recordSession(duration: TimeInterval?, wordCount: Int, characterCount: Int) {
        recordSessionCallCount += 1
        recordSessionLastDuration = duration
        recordSessionLastWordCount = wordCount
        recordSessionLastCharacterCount = characterCount

        // Update snapshot to simulate real behavior
        var updated = snapshot
        updated.totalSessions += 1
        if let duration = duration {
            updated.totalDuration += duration
        }
        updated.totalWords += wordCount
        updated.totalCharacters += characterCount
        updated.lastUpdated = Date()
        snapshot = updated
    }

    func getDailyActivity(days: Int) -> [Date: Int] {
        getDailyActivityCallCount += 1
        getDailyActivityLastDays = days

        // Return configured data or generate empty data for the requested days
        if !dailyActivityData.isEmpty {
            return dailyActivityData
        }

        let calendar = Calendar.current
        var result: [Date: Int] = [:]
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let startOfDay = calendar.startOfDay(for: date)
            result[startOfDay] = 0
        }
        return result
    }

    func calculateStreak() -> Int {
        calculateStreakCallCount += 1
        return streakValue
    }

    func rebuild(using records: [TranscriptionRecord]) {
        rebuildCallCount += 1
        var rebuilt = UsageSnapshot.empty
        for record in records {
            rebuilt.totalSessions += 1
            if let duration = record.duration {
                rebuilt.totalDuration += duration
            }
            rebuilt.totalWords += record.wordCount
            rebuilt.totalCharacters += record.text.count
        }
        rebuilt.lastUpdated = Date()
        snapshot = rebuilt
    }

    func rebuildDailyActivity(using records: [TranscriptionRecord]) {
        rebuildDailyActivityCallCount += 1
    }

    func reset() {
        resetCallCount += 1
        snapshot = .empty
    }

    func bootstrapIfNeeded(dataManager: DataManagerProtocol) async {
        bootstrapIfNeededCallCount += 1
    }

    // MARK: - Test Helpers

    func resetMock() {
        snapshot = .empty
        dailyActivityData = [:]
        streakValue = 0

        recordSessionCallCount = 0
        recordSessionLastDuration = nil
        recordSessionLastWordCount = nil
        recordSessionLastCharacterCount = nil
        getDailyActivityCallCount = 0
        getDailyActivityLastDays = nil
        calculateStreakCallCount = 0
        rebuildCallCount = 0
        rebuildDailyActivityCallCount = 0
        resetCallCount = 0
        bootstrapIfNeededCallCount = 0
    }

    func setSnapshot(_ newSnapshot: UsageSnapshot) {
        snapshot = newSnapshot
    }

    func setDailyActivity(_ activity: [Date: Int]) {
        dailyActivityData = activity
    }

    func setStreak(_ streak: Int) {
        streakValue = streak
    }
}
