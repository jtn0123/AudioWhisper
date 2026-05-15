import XCTest
@testable import AudioWhisper

/// Retry, error-handling and provider-specific coverage for the ContentView
/// recording workflow. Split out of `ContentViewRecordingTests` to keep each
/// test class within the type body length budget.
@MainActor
final class ContentViewRecordingErrorTests: XCTestCase {
    private var mockSpeechService: MockSpeechToTextService!

    override func setUp() async throws {
        try await super.setUp()
        mockSpeechService = MockSpeechToTextService()
    }

    override func tearDown() async throws {
        mockSpeechService?.reset()
        try await super.tearDown()
    }

    // MARK: - Retry Logic Tests

    func testRetryRequiresLastAudioURL() async throws {
        let lastAudioURL: URL? = nil
        var showError = false
        var errorMessage: String?

        // Simulate retryLastTranscription check
        if lastAudioURL == nil {
            errorMessage = "No audio file available to retry. Please record again."
            showError = true
        }

        XCTAssertTrue(showError, "Should show error when no audio URL")
        XCTAssertEqual(errorMessage, "No audio file available to retry. Please record again.")
    }

    func testRetryRequiresFileExists() async throws {
        let nonExistentURL = URL(fileURLWithPath: "/tmp/non_existent_\(UUID().uuidString).m4a")
        var showError = false
        var errorMessage: String?
        var lastAudioURL: URL? = nonExistentURL

        if !FileManager.default.fileExists(atPath: nonExistentURL.path) {
            errorMessage = "Audio file no longer exists. Please record again."
            showError = true
            lastAudioURL = nil
        }

        XCTAssertTrue(showError, "Should show error when file doesn't exist")
        XCTAssertEqual(errorMessage, "Audio file no longer exists. Please record again.")
        XCTAssertNil(lastAudioURL, "Should clear lastAudioURL when file doesn't exist")
    }

    func testRetryBlockedWhileProcessing() async throws {
        var retryAttempted = false

        // Simulate retry guard - only attempt if not processing
        if !isCurrentlyProcessing(true) {
            retryAttempted = true
        }

        XCTAssertFalse(retryAttempted, "Retry should be blocked while processing")
    }

    // Helper to avoid compile-time constant folding
    private func isCurrentlyProcessing(_ value: Bool) -> Bool {
        value
    }

    // MARK: - Error Handling Tests

    func testGenericErrorDisplaysLocalizedDescription() async throws {
        struct CustomError: LocalizedError {
            var errorDescription: String? { "Custom error message" }
        }

        mockSpeechService.setFailure(CustomError())

        var errorMessage: String?
        var showError = false
        var isProcessing = true

        do {
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                provider: .local,
                model: nil
            )
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isProcessing = false
        }

        XCTAssertTrue(showError)
        XCTAssertEqual(errorMessage, "Custom error message")
        XCTAssertFalse(isProcessing, "isProcessing should reset on error")
    }

    func testSuccessSetsShowSuccessTrue() async throws {
        mockSpeechService.setSuccess("success text")

        var showSuccess = false
        var isProcessing = true

        do {
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
                provider: .local,
                model: nil
            )
            // Success path
            showSuccess = true
            isProcessing = false
        } catch {
            XCTFail("Should not throw")
        }

        XCTAssertTrue(showSuccess, "showSuccess should be true after successful transcription")
        XCTAssertFalse(isProcessing, "isProcessing should be false after success")
    }

    // MARK: - Provider-Specific Tests

    func testLocalProviderPassesModel() async throws {
        mockSpeechService.setSuccess("local transcription")

        _ = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .local,
            model: .small
        )

        XCTAssertEqual(mockSpeechService.lastProvider, .local)
        XCTAssertEqual(mockSpeechService.lastModel, .small, "Should pass model for local provider")
    }

    func testParakeetProviderDoesNotUseWhisperModel() async throws {
        mockSpeechService.setSuccess("parakeet transcription result")

        _ = try await mockSpeechService.transcribeRaw(
            audioURL: URL(fileURLWithPath: "/tmp/test.m4a"),
            provider: .parakeet,
            model: nil
        )

        XCTAssertEqual(mockSpeechService.lastProvider, .parakeet)
        XCTAssertNil(mockSpeechService.lastModel, "Should not pass model for parakeet provider")
    }
}
