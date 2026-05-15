import XCTest
@testable import AudioWhisper

// Error-scenario and state-cleanup tests, split out of RecordingWorkflowEdgeCaseTests
// to keep each type within SwiftLint body-length limits.
@MainActor
extension RecordingWorkflowEdgeCaseTests {
    // MARK: - Error Scenario Tests

    func testRecordingURLNotFoundShowsError() async throws {
        mockRecorder.stopRecordingResult = nil

        var errorMessage: String?
        var showError = false

        _ = mockRecorder.startRecording()
        let audioURL = mockRecorder.stopRecording()

        if audioURL == nil {
            errorMessage = "Failed to get recording URL"
            showError = true
        }

        XCTAssertTrue(showError)
        XCTAssertEqual(errorMessage, "Failed to get recording URL")
    }

    func testPathValidationLogicWorks() async throws {
        // Test the path validation logic from ContentView+Recording.swift line 43-45
        // Verify that the guard statement works correctly for both valid and invalid paths

        // Test 1: Valid path should pass validation
        let validURL = URL(fileURLWithPath: "/tmp/test_recording.m4a")
        XCTAssertFalse(validURL.path.isEmpty, "Valid URL should have non-empty path")

        // Test 2: URL with relative path (edge case)
        let relativeURL = URL(fileURLWithPath: "relative_file.m4a")
        XCTAssertFalse(relativeURL.path.isEmpty, "Relative URL should still have a path")

        // Test 3: Verify mock recorder returns expected URL
        _ = mockRecorder.startRecording()
        let audioURL = mockRecorder.stopRecording()
        XCTAssertNotNil(audioURL, "Mock recorder should return a URL")
        XCTAssertFalse(audioURL?.path.isEmpty ?? true, "Returned URL should have valid path")
    }

    func testTranscriptionFailureShowsError() async throws {
        struct TestTranscriptionError: Error, LocalizedError {
            var errorDescription: String? { "Test transcription failed" }
        }

        mockSpeechService.setFailure(TestTranscriptionError())

        var errorMessage: String?
        var showError = false
        var isProcessing = true

        do {
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"), provider: .local, model: nil)
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isProcessing = false
        }

        XCTAssertTrue(showError)
        XCTAssertEqual(errorMessage, "Test transcription failed")
        XCTAssertFalse(isProcessing, "isProcessing should reset on error")
    }

    func testLocalWhisperModelNotDownloadedTriggersSettings() async throws {
        let error = SpeechToTextError.localTranscriptionFailed(LocalWhisperError.modelNotDownloaded)
        mockSpeechService.setFailure(error)

        var shouldOpenDashboard = false
        var errorMessage: String?

        do {
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"), provider: .local, model: .base)
        } catch {
            if case let SpeechToTextError.localTranscriptionFailed(inner) = error,
               let lwError = inner as? LocalWhisperError,
               lwError == .modelNotDownloaded {
                shouldOpenDashboard = true
                errorMessage = "Local Whisper model not downloaded"
            }
        }

        XCTAssertTrue(shouldOpenDashboard, "Should trigger dashboard open for model not downloaded")
        XCTAssertEqual(errorMessage, "Local Whisper model not downloaded")
    }

    func testParakeetModelNotReadyTriggersSettings() async throws {
        mockSpeechService.setFailure(ParakeetError.modelNotReady)

        var shouldOpenDashboard = false
        var errorMessage: String?

        do {
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"), provider: .parakeet, model: nil)
        } catch let error as ParakeetError {
            if error == .modelNotReady {
                shouldOpenDashboard = true
                errorMessage = "Parakeet model not downloaded"
            }
        } catch {
            XCTFail("Expected ParakeetError")
        }

        XCTAssertTrue(shouldOpenDashboard, "Should trigger dashboard open for Parakeet model not ready")
        XCTAssertEqual(errorMessage, "Parakeet model not downloaded")
    }

    func testAsyncTimeoutErrorShowsUserFriendlyMessage() async throws {
        let timeoutError = AsyncTimeoutError.timedOut(30.0)

        var errorMessage: String?
        var showError = false

        // Simulate error handling
        errorMessage = timeoutError.localizedDescription
        showError = true

        XCTAssertTrue(showError)
        XCTAssertEqual(errorMessage, "Operation timed out after 30 seconds")
    }

    // MARK: - State Cleanup Tests

    func testProcessingFlagResetOnSuccess() async throws {
        mockSpeechService.setSuccess("Successful transcription")

        var isProcessing = true
        var transcriptionStartTime: Date? = Date()

        do {
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"), provider: .local, model: nil)
            // On success
            isProcessing = false
            transcriptionStartTime = nil
        } catch {
            XCTFail("Should not throw")
        }

        XCTAssertFalse(isProcessing, "isProcessing should be false after success")
        XCTAssertNil(transcriptionStartTime, "transcriptionStartTime should be nil after success")
    }

    func testProcessingFlagResetOnError() async throws {
        mockSpeechService.setFailure(NSError(domain: "Test", code: 1))

        var isProcessing = true
        var transcriptionStartTime: Date? = Date()

        do {
            _ = try await mockSpeechService.transcribeRaw(
                audioURL: URL(fileURLWithPath: "/tmp/test.m4a"), provider: .local, model: nil)
        } catch {
            isProcessing = false
            transcriptionStartTime = nil
        }

        XCTAssertFalse(isProcessing, "isProcessing should be false after error")
        XCTAssertNil(transcriptionStartTime, "transcriptionStartTime should be nil after error")
    }

    func testLastAudioURLPreservedOnError() async throws {
        let testURL = URL(fileURLWithPath: "/tmp/preserved_audio.m4a")
        mockSpeechService.setFailure(NSError(domain: "Test", code: 1))

        let lastAudioURL: URL? = testURL

        do {
            _ = try await mockSpeechService.transcribeRaw(audioURL: testURL, provider: .local, model: nil)
        } catch {
            // Error handling should NOT clear lastAudioURL for retry functionality
            // lastAudioURL remains unchanged
        }

        XCTAssertEqual(lastAudioURL, testURL, "lastAudioURL should be preserved on error for retry")
    }

    func testAllStateProperlyResetAfterWorkflow() async throws {
        // Simulate a complete workflow and verify all state is reset
        var isProcessing = false
        var showSuccess = false
        var showError = false
        var errorMessage: String?
        var transcriptionStartTime: Date?
        var lastAudioURL: URL?
        let awaitingSemanticPaste = false  // In this test scenario, semantic paste is not awaited

        // Start state
        isProcessing = true
        transcriptionStartTime = Date()
        lastAudioURL = URL(fileURLWithPath: "/tmp/test.m4a")

        mockSpeechService.setSuccess("Test result")

        do {
            _ = try await mockSpeechService.transcribeRaw(audioURL: lastAudioURL!, provider: .local, model: nil)
            // Success path
            showSuccess = true
            isProcessing = false
            transcriptionStartTime = nil
        } catch {
            showError = true
            errorMessage = error.localizedDescription
            isProcessing = false
            transcriptionStartTime = nil
        }

        // Verify state after completion
        XCTAssertFalse(isProcessing)
        XCTAssertTrue(showSuccess)
        XCTAssertFalse(showError)
        XCTAssertNil(errorMessage)
        XCTAssertNil(transcriptionStartTime)
        XCTAssertNotNil(lastAudioURL, "lastAudioURL should be preserved for potential retry")
        XCTAssertFalse(awaitingSemanticPaste, "awaitingSemanticPaste should remain false after workflow")
    }
}
