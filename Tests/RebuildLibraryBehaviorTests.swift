import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildLibraryBehaviorTests: IsolatedXCTestCase {
    override func setUp() {
        super.setUp()
        AppDefaults.transcriptionHistoryEnabled = true
    }

    func testLoadingEmptyAndDisabledLibraryAreDistinct() async throws {
        let history = MockDataManager()
        let state = RebuildLibraryState(history: history)
        let view = RebuildLibraryView(state: state)
        _ = try view.inspect().find(ViewType.ProgressView.self)
        XCTAssertThrowsError(try view.inspect().find(text: "Room for your next idea"))
        await state.load(reset: true, enabled: true)
        _ = try view.inspect().find(text: "Room for your next idea")
        XCTAssertThrowsError(try view.inspect().find(ViewType.ProgressView.self))
        AppDefaults.transcriptionHistoryEnabled = false
        let disabled = RebuildLibraryView(state: state)
        _ = try disabled.inspect().find(text: "Your library is off")
        try disabled.inspect().find(button: "Save future transcripts").tap()
        XCTAssertTrue(AppDefaults.transcriptionHistoryEnabled)
    }

    func testCorrectedTranscriptExpansionPreservesAndRevealsOriginalWords() async throws {
        let history = MockDataManager()
        let original = "the exact original words before cleanup"
        let record = TranscriptionRecord(
            text: String(repeating: "A longer corrected paragraph. ", count: 20), provider: .local,
            wordCount: 80, originalText: original)
        history.recordsToReturn = [record]
        let state = RebuildLibraryState(history: history)
        await state.load(reset: true, enabled: true)
        let view = RebuildLibraryView(state: state)
        _ = try view.inspect().find(text: "Cleaned up")
        XCTAssertThrowsError(try view.inspect().find(text: original))
        try view.inspect().find(button: "Show more").tap()
        XCTAssertTrue(state.expanded.contains(record.id))
        try view.inspect().find(button: "Original transcript").tap()
        _ = try view.inspect().find(text: original)
        XCTAssertTrue(state.showingOriginal.contains(record.id))
        try view.inspect().find(button: "Hide original").tap()
        XCTAssertFalse(state.showingOriginal.contains(record.id))
        try view.inspect().find(button: "Show less").tap()
        XCTAssertFalse(state.expanded.contains(record.id))
        XCTAssertEqual(record.originalText, original)
        XCTAssertEqual(history.deleteRecordCallCount, 0)
    }

    func testFailedFetchOffersARealRetryThatRestoresTheLibrary() async throws {
        let history = MockDataManager()
        history.shouldThrowOnFetch = true
        let state = RebuildLibraryState(history: history)
        await state.load(reset: true, enabled: true)
        let view = RebuildLibraryView(state: state)
        _ = try view.inspect().find(text: "Mock error")
        history.shouldThrowOnFetch = false
        history.recordsToReturn = [TranscriptionRecord(text: "Recovered fixture", provider: .parakeet)]
        try view.inspect().find(button: "Try again").tap()
        try await waitFor { state.error == nil && !state.records.isEmpty }
        _ = try view.inspect().find(text: "Recovered fixture")
        XCTAssertThrowsError(try view.inspect().find(button: "Try again"))
        XCTAssertEqual(history.fetchRecordsCallCount, 2)
    }

    func testNoSearchResultsOffersClearSearchWithoutChangingSavedRecords() async throws {
        let history = MockDataManager()
        history.recordsToReturn = [TranscriptionRecord(text: "Saved fixture", provider: .local)]
        let state = RebuildLibraryState(history: history)
        state.search = "no-match-123"
        await state.load(reset: true, enabled: true)
        let view = RebuildLibraryView(state: state)
        _ = try view.inspect().find(text: "No matching transcripts")
        try view.inspect().find(button: "Clear search").tap()
        XCTAssertEqual(state.search, "")
        await state.load(reset: true, enabled: true)
        _ = try view.inspect().find(text: "Saved fixture")
        XCTAssertEqual(history.recordsToReturn.count, 1)
    }

    func testLoadMoreAppendsTheRemainingPageAndThenRemovesItsControl() async throws {
        let history = MockDataManager()
        history.recordsToReturn = (0..<53).map { TranscriptionRecord(text: "Fixture \($0)", provider: .local) }
        let state = RebuildLibraryState(history: history)
        await state.load(reset: true, enabled: true)
        let view = RebuildLibraryView(state: state)
        XCTAssertEqual(state.records.count, 50)
        try view.inspect().find(button: "Load more").tap()
        try await waitFor { state.records.count == 53 }
        XCTAssertEqual(Set(state.records.map(\.id)).count, 53)
        XCTAssertThrowsError(try view.inspect().find(button: "Load more"))
    }

    func testCancelledFetchFailureDoesNotPublishAStaleError() async {
        let history = MockDataManager()
        history.shouldThrowOnFetch = true
        let state = RebuildLibraryState(history: history)
        let request = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await state.load(reset: true, enabled: true)
        }
        await request.value
        XCTAssertNil(state.error)
        XCTAssertFalse(state.loaded)
        XCTAssertFalse(state.loading)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition(), "Library action did not publish the required state")
    }
}
