import SwiftData
import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildLibraryOperationsTests: IsolatedXCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        AppDefaults.transcriptionHistoryEnabled = true
    }

    func testDeleteControlWaitsForConfirmationThenRefreshesOnlyAfterSuccess() async throws {
        let history = MockDataManager()
        history.recordsToReturn = [TranscriptionRecord(text: "Disposable fixture", provider: .local)]
        let state = RebuildLibraryState(history: history)
        await state.load(reset: true, enabled: true)
        let view = RebuildLibraryView(state: state)
        try view.inspect().find(button: "Delete").tap()
        XCTAssertTrue(state.confirmDelete)
        XCTAssertEqual(history.deleteRecordCallCount, 0)
        XCTAssertNotNil(state.pendingDelete)
        let dialog = try view.inspect().vStack().confirmationDialog(1)
        try dialog.actions().find(button: "Delete transcript").tap()
        try await waitFor { history.deleteRecordCallCount == 1 && state.pendingDelete == nil }
        XCTAssertTrue(state.records.isEmpty)
        _ = try view.inspect().find(text: "Room for your next idea")
    }

    func testDeleteAndClearFailuresKeepRecordsAndShowTheError() async throws {
        let history = MockDataManager()
        let record = TranscriptionRecord(text: "Kept fixture", provider: .local)
        history.recordsToReturn = [record]
        let state = RebuildLibraryState(history: history)
        await state.load(reset: true, enabled: true)
        history.shouldThrowOnDelete = true
        state.pendingDelete = record
        await state.deletePending()
        XCTAssertEqual(state.records.count, 1)
        XCTAssertNil(state.pendingDelete)
        _ = try RebuildLibraryView(state: state).inspect().find(text: "Mock error")
        await state.clear()
        XCTAssertEqual(history.recordsToReturn.count, 1)
        XCTAssertEqual(state.error, "Mock error")
        history.shouldThrowOnDelete = false
        state.confirmClear = true
        let view = RebuildLibraryView(state: state)
        try view.inspect().vStack().confirmationDialog().actions().find(button: "Clear library").tap()
        try await waitFor { state.records.isEmpty && state.error == nil }
        XCTAssertTrue(history.recordsToReturn.isEmpty)
    }

    func testExportPublishesProgressBlocksDeletionAndCanBeCancelledWithoutReplacingAFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ui-export-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("export.txt")
        try "Existing file".write(to: file, atomically: true, encoding: .utf8)
        let history = MockDataManager()
        history.sharedModelContainer = try ModelContainer(
            for: TranscriptionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(try XCTUnwrap(history.sharedModelContainer))
        for index in 0..<501 { context.insert(TranscriptionRecord(text: "Fixture \(index)", provider: .local)) }
        try context.save()
        history.recordsToReturn = [TranscriptionRecord(text: "UI fixture", provider: .local)]
        let state = RebuildLibraryState(history: history, exporter: { container, url, progress in
            try await HistoryExporter.export(container: container, to: url) { count in
                await progress(count)
                try? await Task.sleep(for: .seconds(10))
            }
        })
        await state.load(reset: true, enabled: true)
        let view = RebuildLibraryView(state: state)
        state.startExport(to: file)
        try await waitFor { state.exportedCount == 500 }
        _ = try view.inspect().find(text: "Exported 500 transcripts…")
        XCTAssertTrue(try view.inspect().find(button: "Exporting…").isDisabled())
        XCTAssertTrue(try view.inspect().find(button: "Delete").isDisabled())
        state.pendingDelete = history.recordsToReturn.first
        await state.deletePending()
        await state.clear()
        XCTAssertEqual(history.deleteRecordCallCount, 0)
        XCTAssertEqual(history.deleteAllRecordsCallCount, 0)
        try view.inspect().find(button: "Cancel export").tap()
        try await waitFor { !state.exporting }
        _ = try view.inspect().find(text: "Export cancelled. Your existing file was kept.")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "Existing file")
    }

    func testSuccessfulAndUnavailableExportsHaveDistinctVisibleOutcomes() async throws {
        let history = MockDataManager()
        let state = RebuildLibraryState(history: history)
        state.startExport(to: URL(fileURLWithPath: "/unused"))
        XCTAssertEqual(state.error, "Your local library is unavailable. Try reopening the app.")
        let container = try ModelContainer(
            for: TranscriptionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        history.sharedModelContainer = container
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ui-export-\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        state.startExport(to: file)
        try await waitFor { !state.exporting }
        _ = try RebuildLibraryView(state: state).inspect().find(text: "Exported 0 transcripts.")
        XCTAssertNil(state.error)
        let broken = RebuildLibraryState(history: history, exporter: { _, _, _ in
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture export failed"])
        })
        broken.startExport(to: file)
        try await waitFor { !broken.exporting }
        _ = try RebuildLibraryView(state: broken).inspect().find(text: "Fixture export failed")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition())
    }
}
