import XCTest
@testable import AudioWhisper

// User-message / extraction / edge-case tests, split out of TranscriptionErrorTests for SwiftLint body-length limits.
extension TranscriptionErrorTests {
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
