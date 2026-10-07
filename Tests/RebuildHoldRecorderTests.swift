import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildHoldRecorderTests: IsolatedXCTestCase {
    private func session(start: ((UUID) async -> Bool)? = nil) -> RebuildSession {
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in XCTFail("These holds must not deliver text") }, save: { _, _, _ in XCTFail("Unexpected save") })
        services.startAsync = start
        let session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        return session
    }

    func testReleaseCannotFinishAReplacementRecordingAfterTheHeldOneWasCancelled() {
        let session = session()
        let hold = RebuildHoldRecorder(session: session)
        hold.keyDown(mode: .hold)
        let held = session.captureIdentity
        session.cancel()
        session.toggleRecording()
        XCTAssertNotEqual(session.captureIdentity, held)
        hold.keyUp(mode: .hold)
        XCTAssertEqual(session.phase, .recording, "The release belongs to the cancelled capture")
        session.cancel()
    }

    func testHoldReleaseFinishesOnlyItsOwnCaptureAndIgnoresDuplicateDownEvents() {
        let session = session()
        let hold = RebuildHoldRecorder(session: session)
        hold.keyDown(mode: .hold)
        let capture = session.captureIdentity
        hold.keyDown(mode: .hold)
        XCTAssertEqual(session.captureIdentity, capture)
        hold.keyUp(mode: .hold)
        XCTAssertEqual(session.phase, .failed, "Finish was attempted; this fixture intentionally supplies no audio")
        hold.keyUp(mode: .hold)
        XCTAssertEqual(session.phase, .failed)
    }

    func testReleaseDuringConnectionCancelsWithoutLateRecording() async throws {
        var pending: CheckedContinuation<Bool, Never>?
        let session = session(start: { _ in await withCheckedContinuation { pending = $0 } })
        let hold = RebuildHoldRecorder(session: session)
        hold.keyDown(mode: .hold)
        while pending == nil { await Task.yield() }
        XCTAssertEqual(session.phase, .starting)
        hold.keyUp(mode: .hold)
        XCTAssertEqual(session.phase, .idle)
        try XCTUnwrap(pending).resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.phase, .idle)
    }

    func testToggleAndResetDoNotLetReleaseFinishARecording() {
        let session = session()
        let hold = RebuildHoldRecorder(session: session)
        hold.keyDown(mode: .toggle)
        hold.keyUp(mode: .toggle)
        XCTAssertEqual(session.phase, .recording)
        session.cancel()
        hold.keyDown(mode: .hold)
        hold.reset()
        hold.keyUp(mode: .hold)
        XCTAssertEqual(session.phase, .recording)
        session.cancel()
        session.readiness.modelInstalled = false
        var setup = 0
        session.openSetup = { setup += 1 }
        hold.keyDown(mode: .hold)
        hold.keyUp(mode: .hold)
        XCTAssertEqual(setup, 1)
        XCTAssertEqual(session.phase, .idle)
    }
}
