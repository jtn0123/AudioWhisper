import SwiftData
import XCTest
@testable import AudioWhisper

/// Tests for the reads in `DataManager+Fetching.swift` — history search and the
/// paginated fetch the history window scrolls through.
///
/// Run against a real in-memory `ModelContainer`, not `MockDataManager`: the
/// behaviour under test is SwiftData's (`#Predicate` search, `fetchLimit` /
/// `fetchOffset`, sort order), and a mock would only test its own array code.
@MainActor
final class DataManagerFetchingTests: XCTestCase {

    private var container: ModelContainer!
    private var manager: DataManager!

    override func setUp() async throws {
        try await super.setUp()
        // `saveTranscription` is gated on `isHistoryEnabled`, and the fixtures
        // are dated 2023, so retention must not expire them. AppDefaults is a
        // per-process scratch suite under test, so this is safe in parallel.
        AppDefaults.defaults.set(true, forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.set(RetentionPeriod.forever.rawValue, forKey: "transcriptionRetentionPeriod")
        container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        manager = DataManager(modelContainer: container)

        // Dated oldest → newest in this order, so newest-first is the reverse.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let fixtures = [
            TranscriptionRecord(text: "Buy milk on the way home", provider: .local, modelUsed: "base"),
            TranscriptionRecord(text: "Quarterly REPORT draft", provider: .parakeet, modelUsed: "parakeet-tdt-0.6b-v3"),
            TranscriptionRecord(text: "Call the dentist", provider: .local, modelUsed: "large-v3-turbo"),
            TranscriptionRecord(text: "Report the bug upstream", provider: .parakeet),
            TranscriptionRecord(text: "Water the plants", provider: .local)
        ]
        for (index, record) in fixtures.enumerated() {
            record.date = base.addingTimeInterval(TimeInterval(index))
            try await manager.saveTranscription(record)
        }
    }

    override func tearDown() async throws {
        AppDefaults.defaults.removeObject(forKey: "transcriptionHistoryEnabled")
        AppDefaults.defaults.removeObject(forKey: "transcriptionRetentionPeriod")
        manager = nil
        container = nil
        try await super.tearDown()
    }

    private let newestFirst = [
        "Water the plants",
        "Report the bug upstream",
        "Call the dentist",
        "Quarterly REPORT draft",
        "Buy milk on the way home"
    ]

    // MARK: - fetchAllRecords

    func testFetchAllRecordsReturnsEveryRecordNewestFirst() async throws {
        let records = try await manager.fetchAllRecords()
        XCTAssertEqual(records.map(\.text), newestFirst)
    }

    func testFetchAllRecordsQuietlyReturnsTheSameRecords() async {
        let records = await manager.fetchAllRecordsQuietly()
        XCTAssertEqual(records.map(\.text), newestFirst)
    }

    // MARK: - fetchRecords(matching:limit:offset:)

    func testAnEmptyQueryReturnsEverythingNewestFirst() async throws {
        let records = try await manager.fetchRecords(matching: "")
        XCTAssertEqual(records.map(\.text), newestFirst)
    }

    func testSearchMatchesTextCaseInsensitively() async throws {
        let records = try await manager.fetchRecords(matching: "report")
        XCTAssertEqual(records.map(\.text), ["Report the bug upstream", "Quarterly REPORT draft"])
    }

    func testSearchMatchesTheProviderName() async throws {
        let records = try await manager.fetchRecords(matching: "parakeet")
        XCTAssertEqual(Set(records.map(\.text)), ["Quarterly REPORT draft", "Report the bug upstream"])
    }

    func testSearchMatchesTheModelUsed() async throws {
        let records = try await manager.fetchRecords(matching: "turbo")
        XCTAssertEqual(records.map(\.text), ["Call the dentist"])
    }

    func testSearchWithNoMatchReturnsNothing() async throws {
        let records = try await manager.fetchRecords(matching: "zebra")
        XCTAssertTrue(records.isEmpty)
    }

    func testSearchHonoursLimitAndOffset() async throws {
        let firstPage = try await manager.fetchRecords(matching: "", limit: 2, offset: 0)
        let secondPage = try await manager.fetchRecords(matching: "", limit: 2, offset: 2)
        XCTAssertEqual(firstPage.map(\.text), Array(newestFirst[0..<2]))
        XCTAssertEqual(secondPage.map(\.text), Array(newestFirst[2..<4]))

        let filtered = try await manager.fetchRecords(matching: "the", limit: 1, offset: 1)
        XCTAssertEqual(filtered.map(\.text), ["Report the bug upstream"])
    }

    // MARK: - fetchRecords(limit:offset:search:)

    func testPaginatedFetchWithoutSearchPagesThroughEverything() async throws {
        var seen: [String] = []
        var offset = 0
        while true {
            let page = try await manager.fetchRecords(limit: 2, offset: offset, search: nil)
            if page.isEmpty { break }
            seen += page.map(\.text)
            offset += 2
        }
        XCTAssertEqual(seen, newestFirst)
    }

    func testPaginatedFetchTreatsAnEmptySearchAsNoSearch() async throws {
        let records = try await manager.fetchRecords(limit: 10, offset: 0, search: "")
        XCTAssertEqual(records.count, newestFirst.count)
    }

    /// Unlike `fetchRecords(matching:)`, the paginated search looks at the text
    /// only — "parakeet" is a provider name and matches no transcript.
    func testPaginatedSearchMatchesTextOnly() async throws {
        let byText = try await manager.fetchRecords(limit: 10, offset: 0, search: "REPORT")
        XCTAssertEqual(byText.map(\.text), ["Report the bug upstream", "Quarterly REPORT draft"])

        let byProvider = try await manager.fetchRecords(limit: 10, offset: 0, search: "parakeet")
        XCTAssertTrue(byProvider.isEmpty)
    }

    func testFetchRecordsQuietlyPassesThroughResults() async {
        let records = await manager.fetchRecordsQuietly(limit: 1, offset: 0, search: "plants")
        XCTAssertEqual(records.map(\.text), ["Water the plants"])
    }

    // MARK: - No container

    /// A DataManager whose store failed to open must report that, not crash or
    /// pretend the history is empty — except through the `Quietly` variants,
    /// whose whole contract is to swallow the error for display code.
    func testEveryReadThrowsWhenThereIsNoContainer() async {
        manager.modelContainer = nil

        await assertContainerUnavailable { _ = try await self.manager.fetchAllRecords() }
        await assertContainerUnavailable { _ = try await self.manager.fetchRecords(matching: "x") }
        await assertContainerUnavailable {
            _ = try await self.manager.fetchRecords(matching: "x", limit: 1, offset: 0)
        }
        await assertContainerUnavailable {
            _ = try await self.manager.fetchRecords(limit: 1, offset: 0, search: nil)
        }
        await assertContainerUnavailable {
            try await self.manager.forEachRecordPage(pageSize: 10) { _ in }
        }
    }

    func testQuietReadsReturnEmptyWhenThereIsNoContainer() async {
        manager.modelContainer = nil

        let all = await manager.fetchAllRecordsQuietly()
        let page = await manager.fetchRecordsQuietly(limit: 5, offset: 0, search: nil)
        XCTAssertTrue(all.isEmpty)
        XCTAssertTrue(page.isEmpty)
    }

    private func assertContainerUnavailable(
        _ body: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await body()
            XCTFail("expected modelContainerUnavailable", file: file, line: line)
        } catch DataManagerError.modelContainerUnavailable {
            // expected
        } catch {
            XCTFail("expected modelContainerUnavailable, got \(error)", file: file, line: line)
        }
    }
}
