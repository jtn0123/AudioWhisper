import XCTest
import ViewInspector
@testable import AudioWhisper

@MainActor
final class RebuildPracticeTests: IsolatedXCTestCase {
    func testPracticeUsesRealSessionButNeverCapturesOrPastesToAnExternalAppOrSavesHistory() async throws {
        AppDefaults.enableSmartPaste = true
        AppDefaults.semanticCorrectionMode = .localMLX
        AppDefaults.playCompletionSound = false
        var copied: [String] = []
        var captured = 0
        var saves = 0
        var shown = 0
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { URL(fileURLWithPath: "/practice.wav") }, cancel: {},
            transcribe: { _, config, _ in
                XCTAssertFalse(config.applySemanticCorrection)
                return TranscriptionResult(text: "My first dictation", correctionOutcome: nil)
            }, copy: { copied.append($0) }, save: { _, _, _ in saves += 1 })
        services.capturePasteDestination = { captured += 1; return nil }
        let session = RebuildSession(services: services)
        session.showRecorder = { shown += 1 }
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.startPractice()
        XCTAssertTrue(session.isPractice)
        XCTAssertEqual(session.phase, .recording)
        XCTAssertEqual(shown, 0, "Practice controls stay in the setup card")
        session.finishRecording()
        for _ in 0..<100 where session.phase != .completed { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(copied, ["My first dictation"])
        XCTAssertEqual(captured, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertFalse(RebuildPracticeView.matches("", expected: ""))
        XCTAssertFalse(RebuildPracticeView.matches("Something else", expected: session.transcript))
        XCTAssertTrue(RebuildPracticeView.matches("My first dictation\n", expected: session.transcript))
        let view = RebuildPracticeView(session: session, copy: { copied.append($0) })
        _ = try view.inspect().find(button: "Copy practice text")
        _ = try view.inspect().find(ViewType.TextEditor.self)
        session.cancel()
    }

    func testPracticeCannotStartThroughMissingPermissionsOrWhileAnotherJobIsBusy() {
        var starts = 0
        var services = RebuildSessionServices(
            start: { _ in starts += 1; return true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in })
        services.capturePasteDestination = { nil }
        let session = RebuildSession(services: services)
        var setup = 0
        session.openSetup = { setup += 1 }
        session.startPractice()
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(setup, 1)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.startPractice()
        session.startPractice()
        XCTAssertEqual(starts, 1)
        session.cancel()
    }
}
