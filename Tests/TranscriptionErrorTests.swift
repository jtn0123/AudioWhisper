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
        // M12: Only classify as pythonConfigurationError when the message also
        // signals a configuration problem ("not found"/"not installed"/"missing"/
        // "configure"/"install"). Generic transcription failures that just happen
        // to mention "python" or "parakeet" should fall through.
        let messages = [
            "Python not configured correctly",
            "Parakeet model not installed",
            "Python is missing required dependencies",
            "Failed to configure parakeet-mlx",
            "Python environment: please install dependencies"
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

    /// M12 regression: messages that mention python/parakeet without a config
    /// signal must NOT be intercepted as pythonConfigurationError.
    func testGenericParakeetErrorIsNotPythonConfigurationError() {
        // "transcription" appears in the message so this should route to
        // .transcriptionFailed, not .pythonConfigurationError.
        let error = TranscriptionError.from(errorMessage: "Parakeet transcription failed - check python")
        if case .pythonConfigurationError = error {
            XCTFail("Expected non-pythonConfigurationError for generic parakeet/python message, got: \(error)")
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
}
