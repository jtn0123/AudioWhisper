import XCTest
@testable import AudioWhisper

/// A dictation that fails while the user is in another app must stay visible
/// in the recorder rather than only in the workspace window.
@MainActor
final class RebuildRecorderOutcomeTests: IsolatedXCTestCase {
    private var session: RebuildSession!
    private var shown = 0
    private var closed = 0
    private var opened = 0
    private var startSucceeds = true
    private var transcribe: (() async throws -> TranscriptionResult)!

    override func setUp() {
        super.setUp()
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        shown = 0
        closed = 0
        opened = 0
        startSucceeds = true
        transcribe = { TranscriptionResult(text: "Words", correctionOutcome: nil) }
        session = RebuildSession(services: RebuildSessionServices(
            start: { _ in self.startSucceeds },
            stop: { FileManager.default.temporaryDirectory.appendingPathComponent("outcome-\(UUID()).wav") },
            cancel: {},
            transcribe: { _, _, _ in try await self.transcribe() },
            copy: { _ in }, save: { _, _, _ in }, interruptionSource: nil))
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.showRecorder = { self.shown += 1 }
        session.closeRecorder = { self.closed += 1 }
        session.openWorkspace = { self.opened += 1 }
        session.outcomeTimeScale = 0.01
    }

    override func tearDown() {
        session.cancel()
        session = nil
        transcribe = nil
        super.tearDown()
    }

    private func failTranscription() async throws {
        transcribe = { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model crashed"]) }
        session.toggleRecording()
        session.finishRecording()
        try await waitFor { self.session.phase == .failed }
    }

    func testTranscriptionFailureKeepsTheRecorderOpenWithTheReason() async throws {
        try await failTranscription()
        XCTAssertEqual(session.recorderOutcome, .failed("Model crashed"))
        XCTAssertEqual(session.notice, "Model crashed", "The workspace still shows it too")
        XCTAssertEqual(shown, 2, "Shown for recording, then again for the failure")
        XCTAssertTrue(session.canRetry, "The recorder can offer Retry because the audio was kept")
    }

    func testOutcomeDismissesItselfAndClosesTheRecorder() async throws {
        try await failTranscription()
        let closedBefore = closed
        try await waitFor { self.session.recorderOutcome == nil }
        XCTAssertEqual(closed, closedBefore + 1)
    }

    func testHoveringHoldsTheOutcomeUntilThePointerLeaves() async throws {
        try await failTranscription()
        session.holdOutcome(true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertNotNil(session.recorderOutcome, "Hover pauses the countdown")
        session.holdOutcome(false)
        try await waitFor { self.session.recorderOutcome == nil }
    }

    func testMicrophoneStartFailureIsShownEvenWithoutAVisibleRecorder() {
        startSucceeds = false
        session.toggleRecording()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.recorderOutcome,
                       .failed("The microphone could not start. Check the selected input and try again."))
        XCTAssertEqual(shown, 1)
    }

    func testRetryFromTheRecorderTranscribesAgainAndKeepsItOpen() async throws {
        try await failTranscription()
        transcribe = { TranscriptionResult(text: "Second try", correctionOutcome: nil) }
        let closedBefore = closed
        session.retryFromRecorder()
        XCTAssertNil(session.recorderOutcome)
        XCTAssertEqual(session.phase, .transcribing)
        XCTAssertEqual(closed, closedBefore, "The recorder stays up to show the new attempt")
        try await waitFor { self.session.phase == .completed }
    }

    func testOpenAndDismissButtonsClearTheOutcome() async throws {
        try await failTranscription()
        session.openWorkspaceFromRecorder()
        XCTAssertEqual(opened, 1)
        XCTAssertNil(session.recorderOutcome)
    }

    func testANewRecordingReplacesALingeringOutcome() async throws {
        try await failTranscription()
        transcribe = { TranscriptionResult(text: "Words", correctionOutcome: nil) }
        session.toggleRecording()
        XCTAssertEqual(session.phase, .recording)
        XCTAssertNil(session.recorderOutcome)
    }

    func testPracticeFailuresStayInTheWorkspace() {
        startSucceeds = false
        session.startPractice()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertNil(session.recorderOutcome)
        XCTAssertEqual(shown, 0)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(condition(), "The session did not reach the expected state")
    }
}
