import Observation
import SwiftData
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildLibraryInvalidationTests: IsolatedXCTestCase {
    private var manager: DataManager!

    override func setUp() async throws {
        try await super.setUp()
        AppDefaults.transcriptionHistoryEnabled = true
        AppDefaults.transcriptionRetentionPeriod = .forever
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        let container = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        manager = DataManager(modelContainer: container)
    }

    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    func testDeliveryInvalidatesMountedLibraryWithoutChangingItsSearch() async throws {
        let query = "matching"
        var records = try await manager.fetchRecords(limit: 50, offset: 0, search: query)
        let updated = expectation(description: "Mounted library observed a committed save")
        let store = manager!
        withObservationTracking {
            _ = store.historyRevision.value
        } onChange: {
            Task { @MainActor in
                records = try await store.fetchRecords(limit: 50, offset: 0, search: query)
                updated.fulfill()
            }
        }
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in false }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "A matching transcript", correctionOutcome: nil) },
            copy: { _ in }, save: { text, _, _ in
                try await store.saveTranscription(TranscriptionRecord(text: text, provider: .local))
            }))
        session.readiness = RebuildReadiness(
            microphoneGranted: false, modelInstalled: true, runtimeReady: true, checking: false)
        session.importAudio(URL(fileURLWithPath: "/tmp/library-fixture.wav"))
        await fulfillment(of: [updated], timeout: 1)
        XCTAssertEqual(records.map(\.text), ["A matching transcript"])
        XCTAssertEqual(query, "matching")
        session.cancel()
    }

    func testDeleteAndRetentionPublishCommittedRevisions() async throws {
        let record = TranscriptionRecord(text: "Delete this fixture", provider: .local)
        try await manager.saveTranscription(record)
        let saved = manager.historyRevision.value
        try await manager.deleteRecord(record)
        XCTAssertEqual(manager.historyRevision.value, saved + 1)
        let expired = TranscriptionRecord(text: "Expired fixture", provider: .local)
        expired.date = Date().addingTimeInterval(-60 * 24 * 60 * 60)
        try await manager.saveTranscription(expired)
        for _ in 0..<20 { await Task.yield() }
        AppDefaults.transcriptionRetentionPeriod = .oneWeek
        let beforeCleanup = manager.historyRevision.value
        try await manager.cleanupExpiredRecords()
        XCTAssertEqual(manager.historyRevision.value, beforeCleanup + 1)
        let remaining = try await manager.fetchAllRecords()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSkippedAndFailedSavesDoNotPublishARevision() async throws {
        let original = manager.historyRevision.value
        AppDefaults.transcriptionHistoryEnabled = false
        try await manager.saveTranscription(TranscriptionRecord(text: "Disabled fixture", provider: .local))
        XCTAssertEqual(manager.historyRevision.value, original)
        AppDefaults.transcriptionHistoryEnabled = true
        manager.modelContainer = nil
        do {
            try await manager.saveTranscription(TranscriptionRecord(text: "Failed fixture", provider: .local))
            XCTFail("Save must fail when no store is available")
        } catch {}
        XCTAssertEqual(manager.historyRevision.value, original)
    }

    func testClearPublishesButNoOpRetentionDoesNot() async throws {
        try await manager.saveTranscription(TranscriptionRecord(text: "Clear fixture", provider: .local))
        let saved = manager.historyRevision.value
        try await manager.cleanupExpiredRecords()
        XCTAssertEqual(manager.historyRevision.value, saved)
        try await manager.deleteAllRecords()
        XCTAssertEqual(manager.historyRevision.value, saved + 1)
        let remaining = try await manager.fetchAllRecords()
        XCTAssertTrue(remaining.isEmpty)
    }
}
