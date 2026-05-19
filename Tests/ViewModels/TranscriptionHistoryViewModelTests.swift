import XCTest
@testable import AudioWhisper

@MainActor
final class TranscriptionHistoryViewModelTests: XCTestCase {

    // MARK: - Helpers

    private func makeRecords(_ count: Int) -> [TranscriptionRecord] {
        (0..<count).map { index in
            let record = TranscriptionRecord(
                text: "Record \(index)",
                provider: .local,
                duration: 1.0
            )
            // Distinct, descending-stable dates so paged fetches are deterministic.
            record.date = Date(timeIntervalSince1970: TimeInterval(count - index))
            return record
        }
    }

    // MARK: - Load

    func testLoadRecordsPopulatesRecords() async {
        let mock = MockDataManager()
        mock.recordsToReturn = makeRecords(3)
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)

        await viewModel.loadRecords(reset: true)

        XCTAssertEqual(viewModel.records.count, 3)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(mock.fetchRecordsCallCount, 1)
        XCTAssertFalse(viewModel.hasMore)
    }

    func testLoadRecordsEmptyResultStillMarksLoaded() async {
        let mock = MockDataManager()
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)

        await viewModel.loadRecords(reset: true)

        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.hasMore)
    }

    func testLoadRecordsPassesSearchTermThrough() async {
        let mock = MockDataManager()
        mock.recordsToReturn = makeRecords(2)
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)

        await viewModel.loadRecords(reset: true, search: "  hello  ")

        XCTAssertEqual(mock.fetchRecordsLastQuery, "hello")
    }

    // MARK: - Pagination

    func testPaginationAdvancesPageAndAppends() async {
        let mock = MockDataManager()
        mock.recordsToReturn = makeRecords(7)
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 3)

        await viewModel.loadRecords(reset: true)
        XCTAssertEqual(viewModel.records.count, 3)
        XCTAssertEqual(viewModel.page, 1)
        XCTAssertTrue(viewModel.hasMore)

        await viewModel.loadRecords()
        XCTAssertEqual(viewModel.records.count, 6)
        XCTAssertEqual(viewModel.page, 2)
        XCTAssertTrue(viewModel.hasMore)

        await viewModel.loadRecords()
        XCTAssertEqual(viewModel.records.count, 7)
        XCTAssertEqual(viewModel.page, 3)
        XCTAssertFalse(viewModel.hasMore)
    }

    func testPaginationEmptyBatchClearsHasMore() async {
        // Bug #43: when the record count is an exact multiple of pageSize,
        // the last full page leaves hasMore true; the follow-up fetch returns
        // an empty batch, which must set hasMore false rather than loop.
        let mock = MockDataManager()
        mock.recordsToReturn = makeRecords(6) // exact multiple of pageSize 3
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 3)

        await viewModel.loadRecords(reset: true)
        XCTAssertEqual(viewModel.records.count, 3)
        XCTAssertTrue(viewModel.hasMore)

        await viewModel.loadRecords()
        XCTAssertEqual(viewModel.records.count, 6)
        // After fetching the last full page, hasMore may still be true.

        await viewModel.loadRecords() // fetches an empty batch
        XCTAssertEqual(viewModel.records.count, 6)
        XCTAssertFalse(viewModel.hasMore, "Empty batch must clear hasMore")
    }

    func testResetReturnsToFirstPage() async {
        let mock = MockDataManager()
        mock.recordsToReturn = makeRecords(7)
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 3)

        await viewModel.loadRecords(reset: true)
        await viewModel.loadRecords()
        XCTAssertEqual(viewModel.page, 2)

        await viewModel.loadRecords(reset: true)
        XCTAssertEqual(viewModel.page, 1)
        XCTAssertEqual(viewModel.records.count, 3)
    }

    // MARK: - Delete

    func testDeleteRecordCallsThroughAndReloads() async {
        let mock = MockDataManager()
        let records = makeRecords(3)
        mock.recordsToReturn = records
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)
        await viewModel.loadRecords(reset: true)

        await viewModel.deleteRecord(records[0])

        XCTAssertEqual(mock.deleteRecordCallCount, 1)
        XCTAssertEqual(mock.deleteRecordLastRecord?.id, records[0].id)
        XCTAssertEqual(viewModel.records.count, 2)
        XCTAssertEqual(viewModel.page, 1)
        XCTAssertFalse(viewModel.records.contains { $0.id == records[0].id })
    }

    func testClearAllRecordsEmptiesAndReloads() async {
        let mock = MockDataManager()
        mock.recordsToReturn = makeRecords(4)
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)
        await viewModel.loadRecords(reset: true)

        await viewModel.clearAllRecords()

        XCTAssertEqual(mock.deleteAllRecordsCallCount, 1)
        XCTAssertTrue(viewModel.records.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
    }

    // MARK: - Error Paths

    func testLoadErrorSetsShowErrorAndMessage() async {
        let mock = MockDataManager()
        mock.shouldThrowOnFetch = true
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)

        await viewModel.loadRecords(reset: true)

        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage.contains("Failed to load transcription history"))
        XCTAssertFalse(viewModel.hasMore)
    }

    func testDeleteErrorSetsShowErrorAndMessage() async {
        let mock = MockDataManager()
        let records = makeRecords(2)
        mock.recordsToReturn = records
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)
        await viewModel.loadRecords(reset: true)

        mock.shouldThrowOnDelete = true
        await viewModel.deleteRecord(records[0])

        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage.contains("Failed to delete record"))
    }

    func testClearAllErrorSetsShowErrorAndMessage() async {
        let mock = MockDataManager()
        mock.recordsToReturn = makeRecords(2)
        let viewModel = TranscriptionHistoryViewModel(dataManager: mock, pageSize: 50)
        await viewModel.loadRecords(reset: true)

        mock.shouldThrowOnDelete = true
        await viewModel.clearAllRecords()

        XCTAssertTrue(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage.contains("Failed to clear all records"))
        XCTAssertFalse(viewModel.isLoading)
    }
}
