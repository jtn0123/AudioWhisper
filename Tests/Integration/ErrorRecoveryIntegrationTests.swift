import XCTest
import SwiftData
@testable import AudioWhisper

/// Integration tests for error recovery scenarios across the application
@MainActor
final class ErrorRecoveryIntegrationTests: XCTestCase {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var mockKeychain: MockKeychainService!
    var testDefaults: UserDefaults!
    var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()

        // Create in-memory model container for testing
        modelContainer = try ModelContainer(
            for: TranscriptionRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)

        // Create isolated UserDefaults for testing
        suiteName = "ErrorRecoveryIntegrationTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!

        // Set up mock keychain
        mockKeychain = MockKeychainService()

        // Enable test environment for ErrorPresenter
        ErrorPresenter.shared.isTestEnvironment = true
    }

    override func tearDown() async throws {
        // Clean up records
        if let modelContext = modelContext {
            let allRecords = try? modelContext.fetch(FetchDescriptor<TranscriptionRecord>())
            for record in allRecords ?? [] {
                modelContext.delete(record)
            }
            try? modelContext.save()
        }

        // Clean up test defaults
        if let suiteName = suiteName {
            testDefaults?.removePersistentDomain(forName: suiteName)
        }

        modelContainer = nil
        modelContext = nil
        mockKeychain = nil
        testDefaults = nil
        suiteName = nil

        try await super.tearDown()
    }

    // MARK: - Helper Methods

    private func waitForAsyncOperation() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    // MARK: - Network Error Recovery Tests

    func testRecoveryFromNetworkErrorDuringTranscription() async throws {
        // Given - A network error scenario
        let networkError = TranscriptionError.networkConnectionError

        // When - Error is presented
        let expectation = expectation(forNotification: .retryRequested, object: nil)

        ErrorPresenter.shared.showError(networkError.userMessage)

        // Then - Retry notification should be posted
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testRecoveryFromNetworkTimeoutError() async throws {
        // Given - A timeout error
        let timeoutError = TranscriptionError.networkTimeout

        // When - Error is presented
        let expectation = expectation(forNotification: .retryRequested, object: nil)

        ErrorPresenter.shared.showError(timeoutError.userMessage)

        // Then - Retry notification should be posted
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - Microphone Permission Error Recovery Tests

    func testRecoveryFromMicrophonePermissionDenied() async throws {
        // Given - A permission denied error
        let permissionError = TranscriptionError.microphonePermissionDenied

        // Then - A microphone error must NOT trigger a retry notification.
        let noRetry = expectation(forNotification: .retryRequested, object: nil)
        noRetry.isInverted = true
        let noRetryTranscription = expectation(
            forNotification: .retryTranscriptionRequested, object: nil)
        noRetryTranscription.isInverted = true

        // When - Error is presented
        ErrorPresenter.shared.showError(permissionError.userMessage)

        await fulfillment(of: [noRetry, noRetryTranscription], timeout: 0.5)
    }

    func testRecoveryFromMicrophonePermissionRestricted() async throws {
        // Given - A restricted permission error
        let restrictedError = TranscriptionError.microphonePermissionRestricted

        // Then - A microphone error must NOT trigger a retry notification.
        let noRetry = expectation(forNotification: .retryRequested, object: nil)
        noRetry.isInverted = true
        let noRetryTranscription = expectation(
            forNotification: .retryTranscriptionRequested, object: nil)
        noRetryTranscription.isInverted = true

        // When - Error is presented
        ErrorPresenter.shared.showError(restrictedError.userMessage)

        await fulfillment(of: [noRetry, noRetryTranscription], timeout: 0.5)
    }

    // MARK: - Audio Processing Error Recovery Tests

    func testRecoveryFromAudioProcessingError() async throws {
        // Given - An audio processing error (not a retryable error type)
        let audioError = TranscriptionError.audioProcessingError

        // Then - No retry notification should be posted for this error type.
        let noRetry = expectation(forNotification: .retryRequested, object: nil)
        noRetry.isInverted = true
        let noRetryTranscription = expectation(
            forNotification: .retryTranscriptionRequested, object: nil)
        noRetryTranscription.isInverted = true

        // When - Error is presented
        ErrorPresenter.shared.showError(audioError.userMessage)

        await fulfillment(of: [noRetry, noRetryTranscription], timeout: 0.5)
    }

    // MARK: - Model Error Recovery Tests

    func testRecoveryFromModelLoadFailure() async throws {
        // Given - A model not found error (not a retryable error type)
        let modelError = TranscriptionError.modelNotFound(model: "large-v3")

        // Then - No retry notification should be posted for this error type.
        let noRetry = expectation(forNotification: .retryRequested, object: nil)
        noRetry.isInverted = true
        let noRetryTranscription = expectation(
            forNotification: .retryTranscriptionRequested, object: nil)
        noRetryTranscription.isInverted = true

        // When - Error is presented
        ErrorPresenter.shared.showError(modelError.userMessage)

        await fulfillment(of: [noRetry, noRetryTranscription], timeout: 0.5)
    }

    // MARK: - Python Configuration Error Recovery Tests

    func testRecoveryFromPythonConfigurationError() async throws {
        // Given - A Python configuration error (not a retryable error type)
        let pythonError = TranscriptionError.pythonConfigurationError

        // Then - No retry notification should be posted for this error type.
        let noRetry = expectation(forNotification: .retryRequested, object: nil)
        noRetry.isInverted = true
        let noRetryTranscription = expectation(
            forNotification: .retryTranscriptionRequested, object: nil)
        noRetryTranscription.isInverted = true

        // When - Error is presented
        ErrorPresenter.shared.showError(pythonError.userMessage)

        await fulfillment(of: [noRetry, noRetryTranscription], timeout: 0.5)
    }

    // MARK: - Retry Mechanism Tests

    func testRetryMechanismAfterTranscriptionFailure() async throws {
        // Given - A transcription failure message that contains "transcription" keyword
        // (ErrorPresenter uses keyword matching to determine error type)
        let errorMessage = "Transcription failed: Audio too short"

        // When - Error is presented
        let expectation = expectation(forNotification: .retryTranscriptionRequested, object: nil)

        ErrorPresenter.shared.showError(errorMessage)

        // Then - Retry transcription notification should be posted
        await fulfillment(of: [expectation], timeout: 2.0)
    }

    // MARK: - State Preservation Tests

    func testErrorRecoveryPreservesAppState() async throws {
        // Given - Existing transcription records
        let existingRecord = TranscriptionRecord(
            text: "Existing transcription before error",
            provider: .local,
            duration: 5.0
        )
        modelContext.insert(existingRecord)
        try modelContext.save()

        // When - An error occurs and is handled
        let networkError = TranscriptionError.networkConnectionError
        ErrorPresenter.shared.showError(networkError.userMessage)

        await waitForAsyncOperation()

        // Then - Existing records should be preserved
        let descriptor = FetchDescriptor<TranscriptionRecord>()
        let records = try modelContext.fetch(descriptor)

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.text, "Existing transcription before error")
    }

    // MARK: - Notification Tests

    func testErrorRecoveryNotificationsPosted() async throws {
        // Test that appropriate notifications are posted for different error types

        // Connection error -> retryRequested
        let connectionExpectation = expectation(forNotification: .retryRequested, object: nil)
        ErrorPresenter.shared.showError("Connection failed, please retry")
        await fulfillment(of: [connectionExpectation], timeout: 2.0)
    }

    // MARK: - Concurrent Error Tests

    func testConcurrentErrorsHandledCorrectly() async throws {
        // Given - Multiple errors occur in quick succession
        let errors = [
            "Connection error occurred",
            "Transcription service failed",
            "Another connection issue"
        ]

        // When - All errors are presented
        let expectations = [
            expectation(forNotification: .retryRequested, object: nil),
            expectation(forNotification: .retryTranscriptionRequested, object: nil),
            expectation(forNotification: .retryRequested, object: nil)
        ]

        for error in errors {
            ErrorPresenter.shared.showError(error)
        }

        // Then - All should be handled without crash
        await fulfillment(of: expectations, timeout: 3.0)
    }

    // MARK: - Error Type Classification Tests

    private struct ErrorClassificationCase {
        let message: String
        let expectsConnection: Bool
        let expectsTranscription: Bool
    }

    func testErrorTypeClassificationIsAccurate() {
        // Test that different error messages are classified correctly
        let testCases: [ErrorClassificationCase] = [
            ErrorClassificationCase(message: "Connection timeout", expectsConnection: true, expectsTranscription: false),
            ErrorClassificationCase(message: "Transcription failed", expectsConnection: false, expectsTranscription: true),
            ErrorClassificationCase(message: "Internet not available", expectsConnection: true, expectsTranscription: false),
            ErrorClassificationCase(message: "Whisper transcription error", expectsConnection: false, expectsTranscription: true)
        ]

        for testCase in testCases {
            let message = testCase.message
            let error = TranscriptionError.from(errorMessage: message)

            if testCase.expectsConnection {
                let isConnectionError: Bool
                switch error {
                case .networkConnectionError, .networkTimeout:
                    isConnectionError = true
                default:
                    isConnectionError = false
                }
                XCTAssertTrue(
                    isConnectionError,
                    "Expected connection-class error for '\(message)', got \(error)"
                )
            }

            if testCase.expectsTranscription {
                guard case .transcriptionFailed = error else {
                    XCTFail("Expected .transcriptionFailed for '\(message)', got \(error)")
                    continue
                }
            }
        }
    }

    // MARK: - Storage Error Tests

    func testRecoveryFromInsufficientStorageError() async throws {
        // Given - A storage error (not a retryable error type)
        let storageError = TranscriptionError.insufficientStorage

        // Then - No retry notification should be posted for this error type.
        let noRetry = expectation(forNotification: .retryRequested, object: nil)
        noRetry.isInverted = true
        let noRetryTranscription = expectation(
            forNotification: .retryTranscriptionRequested, object: nil)
        noRetryTranscription.isInverted = true

        // When - Error is presented
        ErrorPresenter.shared.showError(storageError.userMessage)

        await fulfillment(of: [noRetry, noRetryTranscription], timeout: 0.5)
    }

    // MARK: - General Error Tests

    func testRecoveryFromGeneralError() async throws {
        // Given - A general error with no retry/connection/transcription keyword
        let generalError = TranscriptionError.generalError(message: "Something unexpected happened")

        // Then - No retry notification should be posted for an unclassified error.
        let noRetry = expectation(forNotification: .retryRequested, object: nil)
        noRetry.isInverted = true
        let noRetryTranscription = expectation(
            forNotification: .retryTranscriptionRequested, object: nil)
        noRetryTranscription.isInverted = true

        // When - Error is presented
        ErrorPresenter.shared.showError(generalError.userMessage)

        await fulfillment(of: [noRetry, noRetryTranscription], timeout: 0.5)
    }
}
