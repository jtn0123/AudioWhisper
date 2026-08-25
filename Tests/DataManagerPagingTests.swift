import SwiftData
import XCTest
@testable import AudioWhisper

/// Tests for `forEachRecordPage`, the paged scan that replaced whole-history
/// fetches on the aggregate paths.
///
/// Audit item B1/G2: `fetchAllRecords()` sets a sort but no `fetchLimit`, so it
/// materialises the entire table. Retention is user-configurable and one of the
/// options is *forever*, so both the usage-metrics rebuild and the dashboard
/// grew linearly with lifetime transcript count. Every other fetch in
/// `DataManager` bounds itself; that one did not.
@MainActor
final class DataManagerPagingTests: XCTestCase {

    private var container: ModelContainer!
    private var manager: DataManager!

    override func setUp() async throws {
        try await super.setUp()
        // `saveTranscription` is gated on `isHistoryEnabled`, which reads
        // AppDefaults. Under test that is a per-process scratch suite, so this
        // write is process-local and safe under `--parallel`.
        AppDefaults.defaults.set(true, forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.set(RetentionPeriod.forever.rawValue,
                                 forKey: "transcriptionRetentionPeriod")

        container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        manager = DataManager(modelContainer: container)
    }

    override func tearDown() async throws {
        AppDefaults.defaults.removeObject(forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.removeObject(forKey: "transcriptionRetentionPeriod")
        manager = nil
        container = nil
        try await super.tearDown()
    }

    /// Records are dated oldest → newest by index, so date-descending order is
    /// the reverse of insertion order.
    private func seed(_ count: Int) async throws {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for index in 0..<count {
            let record = TranscriptionRecord(
                text: "record \(index)",
                provider: index.isMultiple(of: 2) ? .parakeet : .local,
                duration: 1,
                wordCount: index,
                characterCount: index * 2
            )
            record.date = base.addingTimeInterval(TimeInterval(index))
            try await manager.saveTranscription(record)
        }
    }

    func testPagingVisitsEveryRecordExactlyOnce() async throws {
        try await seed(25)

        var seen: [String] = []
        try await manager.forEachRecordPage(pageSize: 10) { page in
            seen.append(contentsOf: page.map(\.text))
        }

        XCTAssertEqual(seen.count, 25, "every record must be visited")
        XCTAssertEqual(Set(seen).count, 25, "no record may be visited twice")
    }

    /// The whole point of the change: peak memory is one page, not the table.
    func testPagingNeverHandsOutMoreThanOnePageAtATime() async throws {
        try await seed(25)

        var pageSizes: [Int] = []
        try await manager.forEachRecordPage(pageSize: 10) { page in
            pageSizes.append(page.count)
        }

        XCTAssertEqual(pageSizes, [10, 10, 5])
        XCTAssertFalse(pageSizes.contains { $0 > 10 }, "no page may exceed the requested size")
    }

    func testPagingPreservesDateDescendingOrder() async throws {
        try await seed(12)

        var dates: [Date] = []
        try await manager.forEachRecordPage(pageSize: 5) { page in
            dates.append(contentsOf: page.map(\.date))
        }

        XCTAssertEqual(dates, dates.sorted(by: >), "paging must preserve newest-first order")
    }

    /// A paged scan must produce byte-identical totals to the whole-table fetch
    /// it replaced — otherwise usage stats would shift the moment this landed.
    func testPagedTotalsMatchWholeTableTotals() async throws {
        try await seed(37)

        let all = try await manager.fetchAllRecords()
        let expectedWords = all.reduce(0) { $0 + $1.wordCount }
        let expectedCharacters = all.reduce(0) { $0 + $1.characterCount }

        var words = 0
        var characters = 0
        var sessions = 0
        try await manager.forEachRecordPage(pageSize: 8) { page in
            for record in page {
                sessions += 1
                words += record.wordCount
                characters += record.characterCount
            }
        }

        XCTAssertEqual(sessions, all.count)
        XCTAssertEqual(words, expectedWords)
        XCTAssertEqual(characters, expectedCharacters)
    }

    func testPagingOnAnEmptyStoreInvokesNothing() async throws {
        var called = false
        try await manager.forEachRecordPage(pageSize: 10) { _ in called = true }
        XCTAssertFalse(called)
    }

    /// A page size that exactly divides the record count must not emit a
    /// trailing empty page, and must not loop forever.
    func testPagingWithExactMultipleTerminatesCleanly() async throws {
        try await seed(20)

        var pageSizes: [Int] = []
        try await manager.forEachRecordPage(pageSize: 10) { page in
            pageSizes.append(page.count)
        }

        XCTAssertEqual(pageSizes, [10, 10], "no trailing empty page")
    }

    /// Guards the `pageSize > 0` early return — without it the offset never
    /// advances and the loop spins forever.
    func testNonPositivePageSizeReturnsWithoutLooping() async throws {
        try await seed(3)

        var called = false
        try await manager.forEachRecordPage(pageSize: 0) { _ in called = true }
        XCTAssertFalse(called)
    }
}
