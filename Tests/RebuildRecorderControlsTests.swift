import XCTest
@testable import AudioWhisper

/// The recorder HUD's controls: it appears while the microphone starts (C5).
@MainActor
final class RebuildRecorderControlsTests: IsolatedXCTestCase {
    private var session: RebuildSession!
    private var shown = 0
    private var release: CheckedContinuation<Bool, Never>?

    override func setUp() {
        super.setUp()
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        AppDefaults.immediateRecording = false
        shown = 0
        var services = RebuildSessionServices(
            start: { _ in true },
            stop: { FileManager.default.temporaryDirectory.appendingPathComponent("controls-\(UUID()).wav") },
            cancel: {},
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
}
