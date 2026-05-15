import XCTest
@testable import AudioWhisper

// MARK: - LocalizedStrings Tests
final class LocalizedStringsCoverageTests: XCTestCase {

    func testUIStringsAreNonEmpty() {
        let strings = [
            LocalizedStrings.UI.ready,
            LocalizedStrings.UI.recording,
            LocalizedStrings.UI.processing,
            LocalizedStrings.UI.success,
            LocalizedStrings.UI.microphoneAccessRequired,
            LocalizedStrings.UI.spaceToRecord
        ]
        strings.forEach { XCTAssertFalse($0.isEmpty) }
    }

    func testAlertStringsAreNonEmpty() {
        let strings = [
            LocalizedStrings.Alerts.errorTitle,
            LocalizedStrings.Alerts.microphoneAccessTitle,
            LocalizedStrings.Alerts.microphoneAccessMessage,
            LocalizedStrings.Alerts.openSystemSettings,
            LocalizedStrings.Alerts.cancel
        ]
        strings.forEach { XCTAssertFalse($0.isEmpty) }
    }

    func testErrorStringsAreNonEmpty() {
        let strings = [
            LocalizedStrings.Errors.failedToStartRecording,
            LocalizedStrings.Errors.failedToGetRecordingURL,
            LocalizedStrings.Errors.recordingURLEmpty,
            LocalizedStrings.Errors.transcriptionFailed,
            LocalizedStrings.Errors.localTranscriptionFailed,
            LocalizedStrings.Errors.fileTooLarge,
            LocalizedStrings.Errors.invalidAudioFile,
            LocalizedStrings.Errors.apiKeyMissing,
            LocalizedStrings.Errors.fileUploadFailed
        ]
        strings.forEach { XCTAssertFalse($0.isEmpty) }
    }

    func testErrorStringsWithFormatSpecifiers() {
        XCTAssertTrue(LocalizedStrings.Errors.transcriptionFailed.contains("%@"))
        XCTAssertTrue(LocalizedStrings.Errors.apiKeyMissing.contains("%@"))
        XCTAssertTrue(LocalizedStrings.Errors.fileUploadFailed.contains("%@"))
    }

    func testLocalWhisperStringsAreNonEmpty() {
        let strings = [
            LocalizedStrings.LocalWhisper.modelNotDownloaded,
            LocalizedStrings.LocalWhisper.invalidAudioFormat,
            LocalizedStrings.LocalWhisper.failedToAllocateBuffer,
            LocalizedStrings.LocalWhisper.noAudioChannelData,
            LocalizedStrings.LocalWhisper.failedToResampleAudio
        ]
        strings.forEach { XCTAssertFalse($0.isEmpty) }
    }

    func testMenuStringsAreNonEmpty() {
        let strings = [
            LocalizedStrings.Menu.record,
            LocalizedStrings.Menu.settings,
            LocalizedStrings.Menu.quit,
            LocalizedStrings.Menu.closeWindow,
            LocalizedStrings.Menu.history
        ]
        strings.forEach { XCTAssertFalse($0.isEmpty) }
    }

    func testSettingsAndAccessibilityStringsAreNonEmpty() {
        XCTAssertFalse(LocalizedStrings.Settings.title.isEmpty)
        XCTAssertFalse(LocalizedStrings.Accessibility.microphoneIcon.isEmpty)
        XCTAssertFalse(LocalizedStrings.Accessibility.recordingButton.isEmpty)
        XCTAssertFalse(LocalizedStrings.Accessibility.progressIndicator.isEmpty)
        XCTAssertFalse(LocalizedStrings.Accessibility.modelDownloadStatus.isEmpty)
    }

    func testKnownDefaultValues() {
        XCTAssertEqual(LocalizedStrings.UI.ready, "Ready")
        XCTAssertEqual(LocalizedStrings.Menu.quit, "Quit")
        XCTAssertEqual(LocalizedStrings.Alerts.cancel, "Cancel")
    }
}
