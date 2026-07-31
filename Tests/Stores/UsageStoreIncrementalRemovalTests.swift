import XCTest
@testable import AudioWhisper

/// B5/G2: `DataManager.deleteRecord` used to fetch every remaining record and
/// call `rebuild(using:)` just to recompute totals, so deleting one transcript
/// cost a full-table load on the main actor. Both stores now subtract the
/// deleted record's contribution instead.
///
/// The contract these tests pin: **incremental removal must agree with a full
/// rebuild from the remaining records.** If it ever diverges, the dashboard
/// starts lying about totals and nothing else would catch it.
@MainActor
final class UsageStoreIncrementalRemovalTests: XCTestCase {

    private func makeRecord(
        words: Int,
        characters: Int,
        duration: TimeInterval?,
        bundleId: String? = nil
    ) -> TranscriptionRecord {
        TranscriptionRecord(
            text: String(repeating: "word ", count: max(0, words)),
            provider: .local,
            duration: duration,
            modelUsed: "base",
            wordCount: words,
            characterCount: characters,
            sourceAppBundleId: bundleId,
            sourceAppName: bundleId.map { "App \($0)" }
        )
    }

    /// SourceUsageStore exposes `allSources()`, not a per-bundle lookup.
    private func stats(_ store: SourceUsageStore, for bundleId: String) -> SourceUsageStats? {
        store.allSources().first { $0.bundleIdentifier == bundleId }
    }

    // MARK: - UsageMetricsStore

    func testRemoveMatchesRebuildForUsageMetrics() {
        let store = UsageMetricsStore.shared
        let all = [
            makeRecord(words: 100, characters: 500, duration: 60),
            makeRecord(words: 250, characters: 1200, duration: 120),
            makeRecord(words: 75, characters: 300, duration: nil)
        ]

        store.rebuild(using: all)
        let removed = all[1]
        store.remove(record: removed)
        let afterIncremental = store.snapshot

        // Authoritative recount from what actually remains.
        store.rebuild(using: [all[0], all[2]])
        let afterRebuild = store.snapshot

        XCTAssertEqual(afterIncremental.totalSessions, afterRebuild.totalSessions)
        XCTAssertEqual(afterIncremental.totalWords, afterRebuild.totalWords)
        XCTAssertEqual(afterIncremental.totalCharacters, afterRebuild.totalCharacters)
        XCTAssertEqual(afterIncremental.totalDuration, afterRebuild.totalDuration, accuracy: 0.0001)
        XCTAssertEqual(afterIncremental.dailyActivity, afterRebuild.dailyActivity)

        store.reset()
    }

    /// A record with no duration must not disturb `totalDuration`.
    func testRemoveHandlesNilDuration() {
        let store = UsageMetricsStore.shared
        let withDuration = makeRecord(words: 10, characters: 50, duration: 90)
        let withoutDuration = makeRecord(words: 20, characters: 100, duration: nil)

        store.rebuild(using: [withDuration, withoutDuration])
        store.remove(record: withoutDuration)

        XCTAssertEqual(store.snapshot.totalDuration, 90, accuracy: 0.0001)
        XCTAssertEqual(store.snapshot.totalWords, 10)
        XCTAssertEqual(store.snapshot.totalSessions, 1)

        store.reset()
    }

    /// Removing more than was ever recorded must floor at zero, never go negative.
    func testRemoveNeverProducesNegativeTotals() {
        let store = UsageMetricsStore.shared
        store.reset()

        store.remove(record: makeRecord(words: 999, characters: 9999, duration: 500))

        XCTAssertEqual(store.snapshot.totalSessions, 0)
        XCTAssertEqual(store.snapshot.totalWords, 0)
        XCTAssertEqual(store.snapshot.totalCharacters, 0)
        XCTAssertEqual(store.snapshot.totalDuration, 0, accuracy: 0.0001)

        store.reset()
    }

    /// The daily-activity bucket must disappear once its last record is removed,
    /// rather than lingering with a zero or negative value.
    func testRemoveClearsEmptiedDailyActivityBucket() {
        let store = UsageMetricsStore.shared
        let only = makeRecord(words: 42, characters: 200, duration: 30)

        store.rebuild(using: [only])
        XCTAssertFalse(store.snapshot.dailyActivity.isEmpty)

        store.remove(record: only)
        XCTAssertTrue(
            store.snapshot.dailyActivity.values.allSatisfy { $0 > 0 },
            "Emptied buckets should be removed, not left at zero/negative"
        )

        store.reset()
    }

    // MARK: - SourceUsageStore

    func testRemoveMatchesRebuildForSourceUsage() {
        let store = SourceUsageStore.shared
        let all = [
            makeRecord(words: 100, characters: 500, duration: 60, bundleId: "com.example.alpha"),
            makeRecord(words: 250, characters: 1200, duration: 120, bundleId: "com.example.alpha"),
            makeRecord(words: 75, characters: 300, duration: 30, bundleId: "com.example.beta")
        ]

        store.rebuild(using: all)
        store.remove(record: all[1])
        let incremental = stats(store, for: "com.example.alpha")

        store.rebuild(using: [all[0], all[2]])
        let rebuilt = stats(store, for: "com.example.alpha")

        XCTAssertEqual(incremental?.totalWords, rebuilt?.totalWords)
        XCTAssertEqual(incremental?.totalCharacters, rebuilt?.totalCharacters)
        XCTAssertEqual(incremental?.sessionCount, rebuilt?.sessionCount)

        store.reset()
    }

    /// An app's entry should disappear once its last record is removed.
    func testRemovingLastRecordDropsTheApp() {
        let store = SourceUsageStore.shared
        let only = makeRecord(words: 10, characters: 40, duration: 5, bundleId: "com.example.solo")

        store.rebuild(using: [only])
        XCTAssertNotNil(stats(store, for: "com.example.solo"))

        store.remove(record: only)
        XCTAssertNil(
            stats(store, for: "com.example.solo"),
            "An app with no remaining sessions should not linger in the stats"
        )

        store.reset()
    }

    /// Records with no source app must be ignored rather than corrupting state.
    func testRemoveIgnoresRecordsWithoutSourceApp() {
        let store = SourceUsageStore.shared
        let tracked = makeRecord(words: 10, characters: 40, duration: 5, bundleId: "com.example.kept")

        store.rebuild(using: [tracked])
        store.remove(record: makeRecord(words: 5, characters: 20, duration: 1, bundleId: nil))

        XCTAssertEqual(stats(store, for: "com.example.kept")?.sessionCount, 1)

        store.reset()
    }
}
