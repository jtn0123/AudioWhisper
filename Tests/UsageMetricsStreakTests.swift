import XCTest
@testable import AudioWhisper

@MainActor
final class UsageMetricsStreakTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: UsageMetricsStore!
    private var suiteName: String!

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    override func setUp() {
        super.setUp()
        suiteName = "UsageMetricsStreakTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = UsageMetricsStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Streak Calculation Tests

    func testStreakStartsAtZeroWithNoActivity() {
        XCTAssertEqual(store.calculateStreak(), 0)
    }

    func testStreakIsOneWithOnlyTodayActivity() {
        store.recordSession(duration: 10, wordCount: 50, characterCount: 250)
        XCTAssertEqual(store.calculateStreak(), 1)
    }

    func testStreakCountsConsecutiveDays() {
        // Set up daily activity for today and yesterday
        let today = Self.dateFormatter.string(from: Date())
        let yesterday = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let twoDaysAgo = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)

        let snapshot = UsageSnapshot(
            totalSessions: 3,
            totalDuration: 30,
            totalWords: 150,
            totalCharacters: 750,
            lastUpdated: Date(),
            dailyActivity: [
                today: 50,
                yesterday: 50,
                twoDaysAgo: 50
            ]
        )
        store.setSnapshotForTesting(snapshot)

        XCTAssertEqual(store.calculateStreak(), 3)
    }

    func testStreakBreaksWithOneGap() {
        // Activity today and 2 days ago, but NOT yesterday
        let today = Self.dateFormatter.string(from: Date())
        let twoDaysAgo = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)

        let snapshot = UsageSnapshot(
            totalSessions: 2,
            totalDuration: 20,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: Date(),
            dailyActivity: [
                today: 50,
                twoDaysAgo: 50
                // Note: yesterday is missing!
            ]
        )
        store.setSnapshotForTesting(snapshot)

        // Streak should only count today since yesterday has no activity
        XCTAssertEqual(store.calculateStreak(), 1)
    }

    func testStreakIsZeroWithNoTodayActivity() {
        // Only activity yesterday, none today
        let yesterday = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        let snapshot = UsageSnapshot(
            totalSessions: 1,
            totalDuration: 10,
            totalWords: 50,
            totalCharacters: 250,
            lastUpdated: Date(),
            dailyActivity: [
                yesterday: 50
            ]
        )
        store.setSnapshotForTesting(snapshot)

        // Streak requires activity today to start counting
        XCTAssertEqual(store.calculateStreak(), 0)
    }

    func testStreakWithZeroWordsDayDoesNotCount() {
        // Today has 0 words (entry exists but empty)
        let today = Self.dateFormatter.string(from: Date())
        let yesterday = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        let snapshot = UsageSnapshot(
            totalSessions: 2,
            totalDuration: 20,
            totalWords: 50,
            totalCharacters: 250,
            lastUpdated: Date(),
            dailyActivity: [
                today: 0,  // Zero words should not count
                yesterday: 50
            ]
        )
        store.setSnapshotForTesting(snapshot)

        XCTAssertEqual(store.calculateStreak(), 0)
    }

    func testStreakWithLongHistory() {
        // 30 consecutive days of activity
        var dailyActivity: [String: Int] = [:]
        for i in 0..<30 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let dateString = Self.dateFormatter.string(from: date)
            dailyActivity[dateString] = 50
        }

        let snapshot = UsageSnapshot(
            totalSessions: 30,
            totalDuration: 300,
            totalWords: 1500,
            totalCharacters: 7500,
            lastUpdated: Date(),
            dailyActivity: dailyActivity
        )
        store.setSnapshotForTesting(snapshot)

        XCTAssertEqual(store.calculateStreak(), 30)
    }

    // MARK: - Daily Activity Cleanup Tests

    func testDailyActivityCleanupRemovesOldEntries() {
        // Create entries beyond 90 days
        var dailyActivity: [String: Int] = [:]

        // Today
        let today = Self.dateFormatter.string(from: Date())
        dailyActivity[today] = 50

        // 89 days ago (should be kept)
        let day89 = Calendar.current.date(byAdding: .day, value: -89, to: Date())!
        dailyActivity[Self.dateFormatter.string(from: day89)] = 50

        // 91 days ago (should be removed)
        let day91 = Calendar.current.date(byAdding: .day, value: -91, to: Date())!
        dailyActivity[Self.dateFormatter.string(from: day91)] = 50

        // 120 days ago (should be removed)
        let day120 = Calendar.current.date(byAdding: .day, value: -120, to: Date())!
        dailyActivity[Self.dateFormatter.string(from: day120)] = 50

        let snapshot = UsageSnapshot(
            totalSessions: 4,
            totalDuration: 40,
            totalWords: 200,
            totalCharacters: 1000,
            lastUpdated: Date(),
            dailyActivity: dailyActivity
        )
        store.setSnapshotForTesting(snapshot)

        // Record a new session which triggers cleanup
        store.recordSession(duration: 10, wordCount: 50, characterCount: 250)

        // Check that old entries were removed
        let updatedDaily = store.snapshot.dailyActivity
        XCTAssertNotNil(updatedDaily[today], "Today should still exist")
        XCTAssertNotNil(updatedDaily[Self.dateFormatter.string(from: day89)], "89 days ago should still exist")
        XCTAssertNil(updatedDaily[Self.dateFormatter.string(from: day91)], "91 days ago should be removed")
        XCTAssertNil(updatedDaily[Self.dateFormatter.string(from: day120)], "120 days ago should be removed")
    }

    // MARK: - getDailyActivity Tests

    func testGetDailyActivityReturnsCorrectDays() {
        let today = Self.dateFormatter.string(from: Date())
        let yesterday = Self.dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        let snapshot = UsageSnapshot(
            totalSessions: 2,
            totalDuration: 20,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: Date(),
            dailyActivity: [
                today: 50,
                yesterday: 75
            ]
        )
        store.setSnapshotForTesting(snapshot)

        let activity = store.getDailyActivity(days: 7)

        XCTAssertEqual(activity.count, 7, "Should return 7 days of data")

        // Find today's value
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        XCTAssertEqual(activity[todayStart], 50)

        let yesterdayStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: Date())!)
        XCTAssertEqual(activity[yesterdayStart], 75)
    }

    func testGetDailyActivityFillsMissingDaysWithZero() {
        // Only today has activity
        let today = Self.dateFormatter.string(from: Date())

        let snapshot = UsageSnapshot(
            totalSessions: 1,
            totalDuration: 10,
            totalWords: 50,
            totalCharacters: 250,
            lastUpdated: Date(),
            dailyActivity: [today: 50]
        )
        store.setSnapshotForTesting(snapshot)

        let activity = store.getDailyActivity(days: 7)

        // Count days with zero
        let zeroDays = activity.values.filter { $0 == 0 }.count
        XCTAssertEqual(zeroDays, 6, "6 of 7 days should have zero activity")
    }

    // MARK: - Word Count Estimation Tests

    func testWordCountWithEmptyString() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: ""), 0)
    }

    func testWordCountWithSingleWord() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello"), 1)
    }

    func testWordCountWithContractions() {
        // Contractions should count as single words
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "don't won't can't"), 3)
    }

    func testWordCountWithNumbers() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "I have 42 apples"), 4)
    }

    func testWordCountWithPunctuation() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "Hello, world! How are you?"), 5)
    }

    func testWordCountWithMultipleSpaces() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello    world"), 2)
    }

    func testWordCountWithNewlines() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello\nworld"), 2)
    }

    func testWordCountWithTabs() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello\tworld"), 2)
    }

    // MARK: - Statistics Calculation Tests

    func testWordsPerMinuteCalculation() {
        // 120 words in 60 seconds = 120 WPM
        let snapshot = UsageSnapshot(
            totalSessions: 1,
            totalDuration: 60,
            totalWords: 120,
            totalCharacters: 600,
            lastUpdated: Date(),
            dailyActivity: [:]
        )
        store.setSnapshotForTesting(snapshot)

        XCTAssertEqual(store.snapshot.wordsPerMinute, 120, accuracy: 0.1)
    }

    func testAverageSessionDurationCalculation() {
        // 2 sessions, 100 seconds total = 50 sec average
        let snapshot = UsageSnapshot(
            totalSessions: 2,
            totalDuration: 100,
            totalWords: 200,
            totalCharacters: 1000,
            lastUpdated: Date(),
            dailyActivity: [:]
        )
        store.setSnapshotForTesting(snapshot)

        XCTAssertEqual(store.snapshot.averageSessionDuration, 50, accuracy: 0.1)
    }

    func testEstimatedTimeSavedCalculation() {
        // 45 words = 1 minute of typing at 45 WPM
        // If transcribed in 10 seconds, saves 50 seconds
        let snapshot = UsageSnapshot(
            totalSessions: 1,
            totalDuration: 10,
            totalWords: 45,
            totalCharacters: 225,
            lastUpdated: Date(),
            dailyActivity: [:]
        )
        store.setSnapshotForTesting(snapshot)

        XCTAssertEqual(store.snapshot.estimatedTimeSaved, 50, accuracy: 1.0)
    }

    func testKeystrokesSavedCalculation() {
        // 100 words * 5 chars/word = 500 keystrokes
        let snapshot = UsageSnapshot(
            totalSessions: 1,
            totalDuration: 60,
            totalWords: 100,
            totalCharacters: 500,
            lastUpdated: Date(),
            dailyActivity: [:]
        )
        store.setSnapshotForTesting(snapshot)

        XCTAssertEqual(store.snapshot.keystrokesSaved, 500)
    }
}
