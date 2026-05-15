import XCTest
@testable import AudioWhisper

/// History-persistence coverage for the ContentView recording workflow.
/// Split out of `ContentViewRecordingTests` to keep each test class within
/// the type body length budget.
@MainActor
final class ContentViewRecordingHistoryTests: XCTestCase {
    private var mockSpeechService: MockSpeechToTextService!
    private var mockDataManager: MockDataManager!

    override func setUp() async throws {
        try await super.setUp()
        mockSpeechService = MockSpeechToTextService()
        mockDataManager = MockDataManager()
    }

    override func tearDown() async throws {
        mockSpeechService?.reset()
        mockDataManager?.reset()
        try await super.tearDown()
    }

    // MARK: - History Save Tests

    func testHistorySavedWhenEnabled() async throws {
        mockDataManager.isHistoryEnabled = true
        mockSpeechService.setSuccess("test transcription for history")

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: nil
        )

        let shouldSave = mockDataManager.isHistoryEnabled
        if shouldSave {
            let record = TranscriptionRecord(
                text: text,
                provider: .local,
                duration: 5.0,
                modelUsed: nil,
                wordCount: 4,
                characterCount: text.count,
                sourceAppBundleId: "com.test.app",
                sourceAppName: "Test App",
                sourceAppIconData: nil
            )
            await mockDataManager.saveTranscriptionQuietly(record)
        }

        XCTAssertEqual(mockDataManager.saveTranscriptionQuietlyCallCount, 1, "Should save when history enabled")
        XCTAssertEqual(mockDataManager.recordsToReturn.count, 1, "Should have one record saved")
        XCTAssertEqual(mockDataManager.recordsToReturn.first?.text, "test transcription for history")
    }

    func testHistorySkippedWhenDisabled() async throws {
        mockDataManager.isHistoryEnabled = false
        mockSpeechService.setSuccess("test transcription no history")

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: nil
        )

        let shouldSave = mockDataManager.isHistoryEnabled
        if shouldSave {
            let record = TranscriptionRecord(
                text: text,
                provider: .local,
                duration: 5.0,
                modelUsed: nil,
                wordCount: 4,
                characterCount: text.count,
                sourceAppBundleId: nil,
                sourceAppName: nil,
                sourceAppIconData: nil
            )
            await mockDataManager.saveTranscriptionQuietly(record)
        }

        XCTAssertEqual(mockDataManager.saveTranscriptionQuietlyCallCount, 0, "Should not save when history disabled")
        XCTAssertTrue(mockDataManager.recordsToReturn.isEmpty, "Should have no records")
    }

    func testHistoryRecordIncludesModelForLocalProvider() async throws {
        mockDataManager.isHistoryEnabled = true
        mockSpeechService.setSuccess("local model transcription")

        let provider = TranscriptionProvider.local
        let model = WhisperModel.base

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: provider,
            model: model
        )

        let modelUsed: String? = (provider == .local) ? model.rawValue : nil

        let record = TranscriptionRecord(
            text: text,
            provider: provider,
            duration: 5.0,
            modelUsed: modelUsed,
            wordCount: 3,
            characterCount: text.count,
            sourceAppBundleId: nil,
            sourceAppName: nil,
            sourceAppIconData: nil
        )
        await mockDataManager.saveTranscriptionQuietly(record)

        XCTAssertEqual(mockDataManager.recordsToReturn.first?.modelUsed, "base",
            "Should include model for local provider")
    }

    func testHistoryRecordExcludesModelForParakeetProvider() async throws {
        mockDataManager.isHistoryEnabled = true
        mockSpeechService.setSuccess("parakeet transcription")

        let provider = TranscriptionProvider.parakeet

        let text = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: provider,
            model: nil
        )

        let modelUsed: String? = (provider == .local) ? WhisperModel.base.rawValue : nil

        let record = TranscriptionRecord(
            text: text,
            provider: provider,
            duration: 5.0,
            modelUsed: modelUsed,
            wordCount: 2,
            characterCount: text.count,
            sourceAppBundleId: nil,
            sourceAppName: nil,
            sourceAppIconData: nil
        )
        await mockDataManager.saveTranscriptionQuietly(record)

        XCTAssertNil(mockDataManager.recordsToReturn.first?.modelUsed,
            "Should not include model for parakeet provider")
    }
}
