import SwiftData
import XCTest
@testable import AudioWhisper

/// Tests for what the Overview page loads (`DashboardHomeView.loadData`) and the
/// merge it relies on, against a real in-memory store.
@MainActor
final class DashboardHomeDataTests: XCTestCase {

    private var container: ModelContainer!
    private var dataManager: DataManager!
    private var defaults: UserDefaults!
    private var suiteName: String!

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }
    private var threeDaysAgo: Date { calendar.date(byAdding: .day, value: -3, to: today)! }

    override func setUp() async throws {
        try await super.setUp()
        AppDefaults.defaults.set(true, forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.set(RetentionPeriod.forever.rawValue, forKey: "transcriptionRetentionPeriod")
        container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        dataManager = DataManager(modelContainer: container)
        suiteName = "DashboardHomeDataTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        AppDefaults.defaults.removeObject(forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.removeObject(forKey: "transcriptionRetentionPeriod")
        defaults.removePersistentDomain(forName: suiteName)
        dataManager = nil
        container = nil
        try await super.tearDown()
    }

    private func save(_ text: String, _ provider: TranscriptionProvider, words: Int, on day: Date, minute: Int) async throws {
        let record = TranscriptionRecord(text: text, provider: provider, duration: 1, wordCount: words)
        record.date = day.addingTimeInterval(TimeInterval(60 * (minute + 1)))
        try await dataManager.saveTranscription(record)
    }

    /// Seven records: five Parakeet today, two Local three days ago.
    private func seed() async throws {
        for index in 0..<5 {
            try await save("parakeet \(index)", .parakeet, words: 10, on: today, minute: index)
        }
        try await save("local 0", .local, words: 5, on: threeDaysAgo, minute: 0)
        try await save("local 1", .local, words: 7, on: threeDaysAgo, minute: 1)
    }

    // MARK: - loadData

    func testRecentRecordsAreTheNewestFiveOnly() async throws {
        try await seed()

        let data = await DashboardHomeView.loadData(
            dataManager: dataManager,
            metricsStore: UsageMetricsStore(defaults: defaults)
        )

        XCTAssertEqual(data.recentRecords.count, DashboardHomeView.recentRecordsDisplayLimit)
        XCTAssertEqual(data.recentRecords.map(\.text), (0..<5).reversed().map { "parakeet \($0)" })
    }

    func testProviderStatsSumWordsPerProviderLargestFirst() async throws {
        try await seed()

        let data = await DashboardHomeView.loadData(
            dataManager: dataManager,
            metricsStore: UsageMetricsStore(defaults: defaults)
        )

        XCTAssertEqual(data.providerStats.map(\.provider), ["parakeet", "local"])
        XCTAssertEqual(data.providerStats.map(\.words), [50, 12])
        XCTAssertEqual(data.providerStats.map(\.icon), ["bird", "laptopcomputer"])
    }

    func testDailyActivityCoversEveryDayWithRecords() async throws {
        try await seed()

        let data = await DashboardHomeView.loadData(
            dataManager: dataManager,
            metricsStore: UsageMetricsStore(defaults: defaults)
        )

        XCTAssertEqual(data.dailyActivity[today], 50)
        XCTAssertEqual(data.dailyActivity[threeDaysAgo], 12)
    }

    /// The first load also rebuilds the usage metrics from history, so the
    /// Overview's headline totals are right on a fresh install of this version.
    func testLoadingBootstrapsAnEmptyMetricsStoreFromHistory() async throws {
        try await seed()
        let store = UsageMetricsStore(defaults: defaults)
        XCTAssertEqual(store.snapshot.totalWords, 0)

        _ = await DashboardHomeView.loadData(dataManager: dataManager, metricsStore: store)

        XCTAssertEqual(store.snapshot.totalSessions, 7)
        XCTAssertEqual(store.snapshot.totalWords, 62)
    }

    func testAnUnavailableStoreLoadsAnEmptyDashboard() async {
        dataManager.modelContainer = nil
        let store = UsageMetricsStore(defaults: defaults)

        let data = await DashboardHomeView.loadData(dataManager: dataManager, metricsStore: store)

        XCTAssertTrue(data.recentRecords.isEmpty)
        XCTAssertTrue(data.providerStats.isEmpty)
        XCTAssertEqual(store.snapshot.totalSessions, 0, "a failed scan must leave the metrics untouched")
    }

    // MARK: - mergeDailyActivity

    /// The store's own figure for a day wins; records only fill days it has no
    /// number for, or a zero.
    func testMergeFromRecordsOnlyBackfillsMissingOrZeroDays() {
        let dayA = today
        let dayB = calendar.date(byAdding: .day, value: -1, to: today)!
        let dayC = calendar.date(byAdding: .day, value: -2, to: today)!
        func record(_ words: Int, on day: Date) -> TranscriptionRecord {
            let record = TranscriptionRecord(text: "x", provider: .local, wordCount: words)
            record.date = day.addingTimeInterval(3600)
            return record
        }

        let merged = DashboardHomeView.mergeDailyActivity(
            base: [dayA: 5, dayB: 0],
            records: [record(100, on: dayA), record(3, on: dayB), record(4, on: dayB), record(7, on: dayC)]
        )

        XCTAssertEqual(merged, [dayA: 5, dayB: 7, dayC: 7])
    }

    func testMergeWithNothingToAddReturnsTheBase() {
        XCTAssertEqual(DashboardHomeView.mergeDailyActivity(base: [today: 3], dailyWords: [:]), [today: 3])
        XCTAssertEqual(DashboardHomeView.mergeDailyActivity(base: [:], records: []), [:])
    }

    // MARK: - numberString

    func testNumberStringUsesLocaleGrouping() {
        XCTAssertEqual(DashboardHomeView.numberString(0), "0")
        XCTAssertEqual(
            DashboardHomeView.numberString(1_234_567),
            NumberFormatter.localizedString(from: 1_234_567, number: .decimal)
        )
    }
}
