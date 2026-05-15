import XCTest
@testable import AudioWhisper

// Button-title / settings-button tests, split out of TranscriptionErrorTests
// to keep each type within SwiftLint body-length limits.
extension TranscriptionErrorTests {
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

}
