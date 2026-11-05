import XCTest
@testable import AudioWhisper

/// The recorder HUD's controls: it appears while the microphone starts (C5)
/// and Esc does what its tooltip promises (C4).
@MainActor
final class RebuildRecorderControlsTests: IsolatedXCTestCase {
    private var session: RebuildSession!
    private var shown = 0
    private var cancels = 0
    private var release: CheckedContinuation<Bool, Never>?

    override func setUp() {
        super.setUp()
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        AppDefaults.immediateRecording = false
        shown = 0
        cancels = 0
        var services = RebuildSessionServices(
            start: { _ in true },
            stop: { FileManager.default.temporaryDirectory.appendingPathComponent("controls-\(UUID()).wav") },
            cancel: { self.cancels += 1 },
            transcribe: { _, _, _ in TranscriptionResult(text: "Words", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }, interruptionSource: nil)
        services.startAsync = { _ in await withCheckedContinuation { self.release = $0 } }
        session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.showRecorder = { self.shown += 1 }
        session.outcomeTimeScale = 0.01
    }

    override func tearDown() {
        release?.resume(returning: false)
        release = nil
        session.cancel()
        session = nil
        super.tearDown()
    }

    private func waitForStart() async throws {
        for _ in 0..<200 where release == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(release, "The microphone start never began")
    }

    func testTheRecorderAppearsWhileTheMicrophoneStarts() async throws {
        session.toggleRecording()
        try await waitForStart()
        XCTAssertEqual(session.phase, .starting)
        XCTAssertEqual(shown, 1, "Shown before the microphone is ready")
    }

    func testExpressModeStillHidesTheRecorderWhileStarting() async throws {
        AppDefaults.immediateRecording = true
        session.toggleRecording()
        try await waitForStart()
        XCTAssertEqual(shown, 0)
    }

    func testEscapeCancelsWhileTheMicrophoneStarts() async throws {
        session.toggleRecording()
        try await waitForStart()
        session.handleEscape()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(cancels, 1)
    }

    func testEscapeCancelsARecording() async throws {
        session.toggleRecording()
        try await waitForStart()
        release?.resume(returning: true)
        release = nil
        for _ in 0..<200 where session.phase != .recording { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(session.phase, .recording)
        session.handleEscape()
        XCTAssertEqual(session.phase, .idle)
    }

    func testEscapeDismissesAnOutcomeInsteadOfCancelling() {
        session.presentFailure("Something broke")
        XCTAssertNotNil(session.recorderOutcome)
        session.handleEscape()
        XCTAssertNil(session.recorderOutcome)
        XCTAssertEqual(session.phase, .failed, "Dismissing doesn't reset the failed dictation")
    }

    func testEscapeDoesNothingWhenIdle() {
        session.handleEscape()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(cancels, 0)
    }
}
