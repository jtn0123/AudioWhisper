import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildUIPolishTests: IsolatedXCTestCase {
    func testElapsedTimeUsesMinutesAndSecondsThenHours() {
        XCTAssertEqual(RebuildElapsedTime.format(0), "00:00")
        XCTAssertEqual(RebuildElapsedTime.format(9.9), "00:09")
        XCTAssertEqual(RebuildElapsedTime.format(75), "01:15")
        XCTAssertEqual(RebuildElapsedTime.format(3_725), "1:02:05")
        XCTAssertEqual(RebuildElapsedTime.format(-4), "00:00", "Clock skew must not show negative time")
    }

    func testRecordingStartTimeIsOnlyExposedWhileRecording() {
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }))
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        XCTAssertNil(session.recordingStartedAt)
        let before = Date()
        session.toggleRecording()
        XCTAssertEqual(session.phase, .recording)
        let start = try? XCTUnwrap(session.recordingStartedAt)
        XCTAssertGreaterThanOrEqual(start ?? .distantPast, before)
        session.cancel()
        XCTAssertNil(session.recordingStartedAt)
    }

    func testWritingInstallMessagesMapToActionableTones() {
        XCTAssertEqual(RebuildWritingView.tone(for: "Error: Download failed (exit code: 1)"), .error)
        XCTAssertEqual(RebuildWritingView.tone(for: "Installation did not finish. Please retry."), .error)
        XCTAssertEqual(RebuildWritingView.tone(for: "Removal failed. The model is still on disk."), .error)
        XCTAssertEqual(RebuildWritingView.tone(for: "Cancelled. Partial files are kept for retry."), .info)
        XCTAssertEqual(RebuildWritingView.tone(for: RebuildWritingInstaller.installedMessage), .success)
    }

    func testNegativeReadinessWordingIsNeverSuccess() {
        for message in [
            "Model not installed", "Correction model is not ready", "Not installed", "Runtime not ready",
            "Downloading model files…", "Already removed", "Installed files are incomplete"
        ] {
            XCTAssertNotEqual(RebuildWritingView.tone(for: message), .success, message)
        }
    }

    func testWritingVerificationToneFollowsResultNotWording() {
        let failed = RebuildWritingStatus.verification(
            ModelVerificationResult(succeeded: false, message: "Verification failed: Correction model is ready"))
        XCTAssertEqual(failed.tone, .error)
        let succeeded = RebuildWritingStatus.verification(
            ModelVerificationResult(succeeded: true, message: "Model not installed elsewhere; this one works"))
        XCTAssertEqual(succeeded.tone, .success)
        struct NotReady: LocalizedError { var errorDescription: String? { "Correction model is ready" } }
        XCTAssertEqual(RebuildWritingStatus.failure(NotReady()).tone, .error)
        XCTAssertEqual(RebuildWritingStatus.removal(stillOnDisk: true).tone, .error)
        XCTAssertEqual(RebuildWritingStatus.removal(stillOnDisk: false).tone, .success)
    }

    func testModelsReadinessRowIsHonestWhileSetupIsBusy() {
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }))
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        let view = RebuildModelsView(session: session)
        XCTAssertEqual(view.readinessStatus.text, "Ready to record")
        XCTAssertEqual(view.readinessStatus.tone, .success)
        session.maintenanceInProgress = true
        XCTAssertNotEqual(view.readinessStatus.tone, .success)
        XCTAssertNotEqual(view.readinessStatus.text, "Ready to record")
        XCTAssertTrue(view.readinessStatus.busy)
    }

    func testLibraryCapsOnlyPreviewsThatCanExpand() {
        XCTAssertFalse(RebuildLibraryView.collapsesPreview(String(repeating: "鷹", count: 300)))
        XCTAssertTrue(RebuildLibraryView.collapsesPreview(String(repeating: "a", count: 361)))
        XCTAssertTrue(RebuildLibraryView.collapsesPreview("1\n2\n3\n4\n5\n6"))
        XCTAssertFalse(RebuildLibraryView.collapsesPreview("1\n2\n3\n4\n5"))
    }

    func testEngineSummaryDropsDownloadSizes() {
        XCTAssertEqual(RebuildRecordView.shortName(ParakeetModel.v2English.displayName), "v2 English")
        XCTAssertEqual(RebuildRecordView.shortName(WhisperModel.largeTurbo.displayName), "Large Turbo")
    }
}
