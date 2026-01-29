import XCTest
@testable import AudioWhisper

/// Comprehensive tests for TranscriptionError enum
final class TranscriptionErrorTests: XCTestCase {

    // MARK: - Error Parsing Tests

    func testMissingAPIKeyFromErrorMessage() {
        let messages = [
            "OpenAI API key is missing",
            "API key not set for Gemini",
            "API_KEY required for transcription",
            "Missing apikey configuration"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .missingAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected missingAPIKey for message: \(message), got: \(error)")
            }
        }
    }

    func testInvalidAPIKeyFromErrorMessage() {
        let messages = [
            "Invalid API key provided",
            "API key unauthorized - please check your key",
            "401 error: API_KEY is invalid",
            "Unauthorized: apikey rejected"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .invalidAPIKey = error {
                // Expected
            } else {
                XCTFail("Expected invalidAPIKey for message: \(message), got: \(error)")
            }
        }
    }

    func testMicrophonePermissionDeniedFromErrorMessage() {
        let messages = [
            "Microphone permission denied",
            "Audio input access denied by user",
            "Recording permission denied"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .microphonePermissionDenied = error {
                // Expected
            } else {
                XCTFail("Expected microphonePermissionDenied for message: \(message), got: \(error)")
            }
        }
    }

    func testMicrophonePermissionRestrictedFromErrorMessage() {
        let messages = [
            "Microphone permission restricted by policy",
            "Audio input access restricted",
            "Recording access restricted"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .microphonePermissionRestricted = error {
                // Expected
            } else {
                XCTFail("Expected microphonePermissionRestricted for message: \(message), got: \(error)")
            }
        }
    }

    func testMicrophoneUnavailableFromErrorMessage() {
        let messages = [
            "Microphone unavailable",
            "Audio input not available",
            "Microphone device not available"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .microphoneUnavailable = error {
                // Expected
            } else {
                XCTFail("Expected microphoneUnavailable for message: \(message), got: \(error)")
            }
        }
    }

    func testNetworkConnectionErrorFromErrorMessage() {
        let messages = [
            "Network connection failed",
            "Connection error occurred",
            "No internet connection available"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .networkConnectionError = error {
                // Expected
            } else {
                XCTFail("Expected networkConnectionError for message: \(message), got: \(error)")
            }
        }
    }

    func testNetworkTimeoutFromErrorMessage() {
        // Note: The implementation checks for "timeout" (not "timed out")
        // and requires both network/connection AND timeout
        let messages = [
            "Network timeout occurred",
            "Connection timeout - request took too long",
            "Network request timeout"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .networkTimeout = error {
                // Expected
            } else {
                XCTFail("Expected networkTimeout for message: \(message), got: \(error)")
            }
        }
    }

    func testTranscriptionFailedFromErrorMessage() {
        let messages = [
            "Transcription failed: audio too short",
            "Whisper transcription error",
            "Gemini transcription service unavailable"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .transcriptionFailed = error {
                // Expected
            } else {
                XCTFail("Expected transcriptionFailed for message: \(message), got: \(error)")
            }
        }
    }

    func testAudioProcessingErrorFromErrorMessage() {
        let messages = [
            "Audio processing failed",
            "Failed to process audio file",
            "Audio convert error occurred"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .audioProcessingError = error {
                // Expected
            } else {
                XCTFail("Expected audioProcessingError for message: \(message), got: \(error)")
            }
        }
    }

    func testModelNotFoundFromErrorMessage() {
        let messages = [
            "Model 'large' not found",
            "Whisper model missing - please download",
            "Model base not found locally"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .modelNotFound = error {
                // Expected
            } else {
                XCTFail("Expected modelNotFound for message: \(message), got: \(error)")
            }
        }
    }

    func testInsufficientStorageFromErrorMessage() {
        let messages = [
            "Insufficient storage space",
            "Not enough disk space available",
            "Storage full - insufficient space for model"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .insufficientStorage = error {
                // Expected
            } else {
                XCTFail("Expected insufficientStorage for message: \(message), got: \(error)")
            }
        }
    }

    func testPythonConfigurationErrorFromErrorMessage() {
        let messages = [
            "Python not configured correctly",
            "Parakeet transcription failed - check python",
            "Python environment error"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .pythonConfigurationError = error {
                // Expected
            } else {
                XCTFail("Expected pythonConfigurationError for message: \(message), got: \(error)")
            }
        }
    }

    func testGeneralErrorFallback() {
        let messages = [
            "Unknown error occurred",
            "Something went wrong",
            "An unexpected issue happened"
        ]

        for message in messages {
            let error = TranscriptionError.from(errorMessage: message)
            if case .generalError(let msg) = error {
                XCTAssertEqual(msg, message)
            } else {
                XCTFail("Expected generalError for message: \(message), got: \(error)")
            }
        }
    }

    // MARK: - Button Title Tests

    func testPrimaryButtonTitleForAllErrorTypes() {
        let expectations: [(TranscriptionError, String)] = [
            (.missingAPIKey(provider: "OpenAI"), "Open Settings"),
            (.invalidAPIKey(provider: "Gemini"), "Open Settings"),
            (.microphonePermissionDenied, "Open System Settings"),
            (.microphonePermissionRestricted, "Open System Settings"),
            (.microphoneUnavailable, "OK"),
            (.networkConnectionError, "OK"),
            (.networkTimeout, "OK"),
            (.transcriptionFailed(reason: "test"), "OK"),
            (.audioProcessingError, "OK"),
            (.modelNotFound(model: "base"), "Download Model"),
            (.insufficientStorage, "Manage Storage"),
            (.pythonConfigurationError, "Configure Python"),
            (.generalError(message: "test"), "OK")
        ]

        for (error, expectedTitle) in expectations {
            XCTAssertEqual(error.primaryButtonTitle, expectedTitle,
                          "Primary button title mismatch for \(error)")
        }
    }

    func testSecondaryButtonTitleForErrorsWithCancel() {
        let errorsWithCancel: [TranscriptionError] = [
            .missingAPIKey(provider: "test"),
            .invalidAPIKey(provider: "test"),
            .microphonePermissionDenied,
            .microphonePermissionRestricted,
            .modelNotFound(model: "test"),
            .pythonConfigurationError
        ]

        for error in errorsWithCancel {
            XCTAssertEqual(error.secondaryButtonTitle, "Cancel",
                          "Expected Cancel button for \(error)")
        }

        let errorsWithoutCancel: [TranscriptionError] = [
            .microphoneUnavailable,
            .networkConnectionError,
            .networkTimeout,
            .transcriptionFailed(reason: "test"),
            .audioProcessingError,
            .insufficientStorage,
            .generalError(message: "test")
        ]

        for error in errorsWithoutCancel {
            XCTAssertNil(error.secondaryButtonTitle,
                        "Expected nil secondary button for \(error)")
        }
    }

    // MARK: - Settings Button Tests

    func testShouldShowSettingsButtonForAPIErrors() {
        let errorsWithSettings: [TranscriptionError] = [
            .missingAPIKey(provider: "test"),
            .invalidAPIKey(provider: "test"),
            .modelNotFound(model: "test"),
            .pythonConfigurationError
        ]

        for error in errorsWithSettings {
            XCTAssertTrue(error.shouldShowSettingsButton,
                         "Expected settings button for \(error)")
        }

        let errorsWithoutSettings: [TranscriptionError] = [
            .microphonePermissionDenied,
            .microphonePermissionRestricted,
            .microphoneUnavailable,
            .networkConnectionError,
            .networkTimeout,
            .transcriptionFailed(reason: "test"),
            .audioProcessingError,
            .insufficientStorage,
            .generalError(message: "test")
        ]

        for error in errorsWithoutSettings {
            XCTAssertFalse(error.shouldShowSettingsButton,
                          "Expected no settings button for \(error)")
        }
    }

    func testShouldShowSystemSettingsForMicErrors() {
        let errorsWithSystemSettings: [TranscriptionError] = [
            .microphonePermissionDenied,
            .microphonePermissionRestricted
        ]

        for error in errorsWithSystemSettings {
            XCTAssertTrue(error.shouldShowSystemSettingsButton,
                         "Expected system settings button for \(error)")
        }

        let errorsWithoutSystemSettings: [TranscriptionError] = [
            .missingAPIKey(provider: "test"),
            .invalidAPIKey(provider: "test"),
            .microphoneUnavailable,
            .networkConnectionError,
            .networkTimeout,
            .transcriptionFailed(reason: "test"),
            .audioProcessingError,
            .modelNotFound(model: "test"),
            .insufficientStorage,
            .pythonConfigurationError,
            .generalError(message: "test")
        ]

        for error in errorsWithoutSystemSettings {
            XCTAssertFalse(error.shouldShowSystemSettingsButton,
                          "Expected no system settings button for \(error)")
        }
    }

    // MARK: - User Message Tests

    func testUserMessageForAllErrorTypes() {
        // Test that all error types have non-empty user messages
        let allErrors: [TranscriptionError] = [
            .missingAPIKey(provider: "OpenAI"),
            .invalidAPIKey(provider: "Gemini"),
            .microphonePermissionDenied,
            .microphonePermissionRestricted,
            .microphoneUnavailable,
            .networkConnectionError,
            .networkTimeout,
            .transcriptionFailed(reason: "Test reason"),
            .audioProcessingError,
            .modelNotFound(model: "base"),
            .insufficientStorage,
            .pythonConfigurationError,
            .generalError(message: "Test error")
        ]

        for error in allErrors {
            XCTAssertFalse(error.userMessage.isEmpty,
                          "User message should not be empty for \(error)")
        }
    }

    func testUserMessageContainsProvider() {
        let error = TranscriptionError.missingAPIKey(provider: "OpenAI")
        XCTAssertTrue(error.userMessage.contains("OpenAI"),
                     "User message should contain provider name")

        let invalidError = TranscriptionError.invalidAPIKey(provider: "Gemini")
        XCTAssertTrue(invalidError.userMessage.contains("Gemini"),
                     "User message should contain provider name")
    }

    func testUserMessageContainsModel() {
        let error = TranscriptionError.modelNotFound(model: "large-v3")
        XCTAssertTrue(error.userMessage.contains("large-v3"),
                     "User message should contain model name")
    }

    func testTranscriptionFailedPreservesReason() {
        let reason = "Audio file was too short for transcription"
        let error = TranscriptionError.transcriptionFailed(reason: reason)
        XCTAssertEqual(error.userMessage, reason,
                      "transcriptionFailed should preserve the reason as user message")
    }

    func testGeneralErrorPreservesMessage() {
        let message = "Custom error message here"
        let error = TranscriptionError.generalError(message: message)
        XCTAssertEqual(error.userMessage, message,
                      "generalError should preserve the message as user message")
    }

    // MARK: - Provider Extraction Tests

    func testExtractProviderFromErrorMessage() {
        let testCases: [(String, String)] = [
            ("OpenAI API key missing", "OpenAI"),
            ("Gemini service unavailable", "Gemini"),
            ("Google API error", "Gemini"),
            ("Whisper model failed", "Whisper"),
            ("Parakeet configuration error", "Parakeet"),
            ("Unknown service API key", "API")  // Default fallback
        ]

        for (message, expectedProvider) in testCases {
            let error = TranscriptionError.from(errorMessage: "\(message) - API key missing")
            if case .missingAPIKey(let provider) = error {
                XCTAssertEqual(provider, expectedProvider,
                              "Expected provider \(expectedProvider) for message: \(message)")
            }
        }
    }

    // MARK: - Model Extraction Tests

    func testExtractModelFromErrorMessage() {
        // Test quoted model name extraction (lowercase "model" to match regex)
        let quotedError = TranscriptionError.from(errorMessage: "The model 'whisper-large-v3' not found")
        if case .modelNotFound(let model) = quotedError {
            XCTAssertEqual(model, "whisper-large-v3")
        } else {
            XCTFail("Expected modelNotFound error")
        }

        // Test common model name extraction (falls back to capitalized model name)
        let commonModels = ["tiny", "base", "small", "medium", "large"]
        for modelName in commonModels {
            let error = TranscriptionError.from(errorMessage: "The \(modelName) model is not found")
            if case .modelNotFound(let model) = error {
                XCTAssertEqual(model, modelName.capitalized,
                              "Expected model \(modelName.capitalized)")
            } else {
                XCTFail("Expected modelNotFound for \(modelName)")
            }
        }
    }

    func testExtractModelFallsBackToUnknown() {
        let error = TranscriptionError.from(errorMessage: "Model not found on disk")
        if case .modelNotFound(let model) = error {
            XCTAssertEqual(model, "Unknown")
        } else {
            XCTFail("Expected modelNotFound error")
        }
    }

    // MARK: - Edge Cases

    func testEmptyErrorMessage() {
        let error = TranscriptionError.from(errorMessage: "")
        if case .generalError(let message) = error {
            XCTAssertEqual(message, "")
        } else {
            XCTFail("Expected generalError for empty message")
        }
    }

    func testCaseInsensitiveMatching() {
        let uppercaseError = TranscriptionError.from(errorMessage: "API KEY MISSING")
        if case .missingAPIKey = uppercaseError {
            // Expected
        } else {
            XCTFail("Should match API key pattern case-insensitively")
        }

        let mixedCaseError = TranscriptionError.from(errorMessage: "MiCrOpHoNe PeRmIsSiOn DeNiEd")
        if case .microphonePermissionDenied = mixedCaseError {
            // Expected
        } else {
            XCTFail("Should match microphone pattern case-insensitively")
        }
    }
}
