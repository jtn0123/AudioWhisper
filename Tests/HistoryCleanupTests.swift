import SwiftData
import XCTest
@testable import AudioWhisper

@MainActor
final class HistoryCleanupTests: IsolatedXCTestCase {
    func testWritingVersionPreservesRecordAndUsageAndSurvivesReload() async throws {
        let container = try ModelContainer(for: TranscriptionRecord.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let record = TranscriptionRecord(text: "Cleaned first result.", provider: .local, duration: 12,
                                         wordCount: 4, characterCount: 21, originalText: "Original stored words.")
        let id = record.id
        let date = record.date
        context.insert(record)
        try context.save()
        let manager = DataManager(modelContainer: container)
        let revision = manager.historyRevision.value
        let version = TranscriptionCleanupVersion(id: UUID(), createdAt: Date(), modeName: "Email",
            text: "Rewritten stored words.", writing: DictationWriting(), modelRepo: "local/model")
        try await manager.appendCleanupVersion(recordID: id, version: version)
        let records = try ModelContext(container).fetch(FetchDescriptor<TranscriptionRecord>())
        let restored = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1, "Reruns must not count as additional dictations")
        XCTAssertEqual(restored.cleanupVersions, [version])
        XCTAssertEqual(restored.text, record.text)
        XCTAssertEqual(restored.originalText, record.originalText)
        XCTAssertEqual(restored.date, date)
        XCTAssertEqual(restored.duration, 12)
        XCTAssertEqual(restored.wordCount, 4)
        XCTAssertEqual(manager.historyRevision.value, revision + 1)
        try await manager.deleteRecord(restored)
        do {
            try await manager.appendCleanupVersion(recordID: id, version: version)
            XCTFail("Deleted records must not be recreated by an old cleanup job")
        } catch { XCTAssertEqual(error as? HistoryCleanupError, .deleted) }
    }

    func testHistoryCleanupStartsFromOriginalAndDoesNotRecognizeOrReformat() async throws {
        let previous = AppDefaults.currentDictationSettings
        defer { AppDefaults.currentDictationSettings = previous }
        var settings = previous
        settings.cleanup = .localMLX
        settings.vocabulary = "Alpha -> Alpha Beta"
        settings.writing.contextSource = .clipboard
        AppDefaults.currentDictationSettings = settings
        let record = TranscriptionRecord(text: "Old cleanup", provider: .local, originalText: "Alpha Beta")
        var inputs: [String] = []
        let state = RebuildHistoryCleanup(record: record, history: MockDataManager(), session: nil) { text, config in
            inputs.append(text)
            XCTAssertNil(config.context)
            XCTAssertEqual(config.writing.contextSource, .none)
            return TranscriptionResult(text: "Preview", correctionOutcome: .applied("Preview"), originalText: text)
        }
        state.run()
        for _ in 0..<100 where state.running { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(inputs, ["Alpha Beta"])
        XCTAssertEqual(state.result, "Preview")
        XCTAssertEqual(record.text, "Old cleanup")
        XCTAssertTrue(record.cleanupVersions.isEmpty, "Generation alone must not save a version")
    }
}
