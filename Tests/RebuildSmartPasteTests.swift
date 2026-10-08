import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildSmartPasteTests: IsolatedXCTestCase {
    private var session: RebuildSession!
    private var foreground: pid_t? = 222
    private var activations = 0
    private var events = 0
    private var copies: [String] = []
    private var activationAccepted = true
    private var terminated = false
    private var destinationAvailable = true
    private var permissionGranted = true

    override func setUp() {
        super.setUp()
        AppDefaults.enableSmartPaste = true
        AppDefaults.playCompletionSound = false
        foreground = 222
        activations = 0
        events = 0
        copies = []
        activationAccepted = true
        terminated = false
        destinationAvailable = true
        permissionGranted = true
        var services = RebuildSessionServices(
            start: { _ in true },
            stop: { FileManager.default.temporaryDirectory.appendingPathComponent("paste-\(UUID()).wav") },
            cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "Captured words", correctionOutcome: nil) },
            copy: { self.copies.append($0) }, save: { _, _, _ in }, interruptionSource: nil)
        services.capturePasteDestination = {
            guard self.destinationAvailable else { return nil }
            return RebuildPasteDestination(
                processIdentifier: 111, bundleIdentifier: "fixture.destination",
                activate: { self.activations += 1; return self.activationAccepted },
                isTerminated: { self.terminated }, foregroundPID: { self.foreground })
        }
        let paste = PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { self.permissionGranted }),
            foregroundPID: { self.foreground }, pasteEvent: { self.events += 1 })
        session = RebuildSession(services: services, paste: paste)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
    }

    override func tearDown() {
        session.cancel()
        session = nil
        super.tearDown()
    }

    func testDelayedActivationPastesExactlyOnceIntoCapturedDestination() async throws {
        record()
        try await waitFor { self.activations == 1 }
        XCTAssertEqual(events, 0)
        XCTAssertNil(session.notice, "Activation in progress is not a paste failure")
        foreground = 111
        try await waitFor { self.events == 1 }
        XCTAssertEqual(copies, ["Captured words"])
        XCTAssertEqual(events, 1)
        XCTAssertNil(session.notice)
    }

    func testAlreadyForegroundDestinationPastesOnce() async throws {
        foreground = 111
        record()
        try await waitFor { self.events == 1 }
        XCTAssertEqual(events, 1)
    }

    func testActivationTimeoutLeavesClipboardAndManualPasteNotice() async throws {
        record()
        try await waitFor { self.session.notice != nil }
        XCTAssertEqual(events, 0)
        XCTAssertEqual(copies, ["Captured words"])
        XCTAssertEqual(session.notice, "Copied. Paste manually with Command V.")
        XCTAssertEqual(session.phase, .completed)
        foreground = 111
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(events, 0, "A late activation must not restart the timed-out paste")
    }

    func testRejectedActivationDoesNotPasteEvenWhenPIDMatches() async throws {
        foreground = 111
        activationAccepted = false
        record()
        try await waitFor { self.session.notice != nil }
        XCTAssertEqual(events, 0)
        XCTAssertEqual(copies, ["Captured words"])
    }

    func testCancelDuringActivationNeverPastesOrPublishesWarning() async throws {
        record()
        try await waitFor { self.activations == 1 }
        session.cancel()
        foreground = 111
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(events, 0)
        XCTAssertNil(session.notice)
        XCTAssertEqual(session.phase, .idle)
    }

    func testReplacementSessionInvalidatesPendingPaste() async throws {
        record()
        try await waitFor { self.activations == 1 }
        session.toggleRecording()
        foreground = 111
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(events, 0)
        XCTAssertNil(session.notice)
        XCTAssertEqual(session.phase, .recording)
    }

    func testDestinationTerminationDuringActivationFallsBackToClipboard() async throws {
        record()
        try await waitFor { self.activations == 1 }
        terminated = true
        foreground = 111
        try await waitFor { self.session.notice != nil }
        XCTAssertEqual(events, 0)
        XCTAssertEqual(copies, ["Captured words"])
    }

    func testMissingDestinationKeepsClipboardOnly() async throws {
        destinationAvailable = false
        record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(events, 0)
        XCTAssertEqual(copies, ["Captured words"])
    }

    func testDisabledSmartPasteDoesNotActivateDestination() async throws {
        AppDefaults.enableSmartPaste = false
        record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(events, 0)
    }

    func testPastePermissionFailureKeepsManualPasteNotice() async throws {
        foreground = 111
        permissionGranted = false
        record()
        try await waitFor { self.session.notice != nil }
        XCTAssertEqual(activations, 1)
        XCTAssertEqual(events, 0)
        XCTAssertEqual(session.notice, "Copied. Paste manually with Command V.")
    }

    private func record() {
        session.toggleRecording()
        session.finishRecording()
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition(), "Smart Paste did not reach the expected state")
    }
}
