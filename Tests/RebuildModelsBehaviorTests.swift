import AVFoundation
import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildModelsBehaviorTests: IsolatedXCTestCase {
    private var requests = 0
    private var starts = 0
    private var openedSetup = 0
    private var permission: AVAuthorizationStatus = .notDetermined
    private var installed = false
    private var runtime = true
    private var installs = 0
    private var install: (() async throws -> Void)?
    private var completion: (@Sendable (Bool) -> Void)?

    private func makeSession() -> RebuildSession {
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        let session = RebuildSession(
            services: RebuildSessionServices(
                start: { _ in self.starts += 1; return true }, stop: { nil }, cancel: {},
                transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
                copy: { _ in }, save: { _, _, _ in }),
            setup: RebuildSetupServices(
                selection: { .current }, microphoneStatus: { self.permission },
                requestMicrophone: { self.requests += 1; self.completion = $0 }, openMicrophoneSettings: {},
                runtimeReady: { _ in self.runtime }, modelInstalled: { _ in self.installed },
                install: { _ in
                    self.installs += 1
                    if let install = self.install { try await install() } else { self.installed = true }
                },
                verify: { _ in ModelVerificationResult(succeeded: true, message: "Fixture verified") }))
        session.openSetup = { self.openedSetup += 1 }
        return session
    }

    func testIncompleteSetupButtonRoutesToSetupWithoutConsentOrCapture() async throws {
        let session = makeSession()
        await session.refreshSetup()
        let view = RebuildModelsView(session: session)
        _ = try view.inspect().find(button: "Allow microphone")
        _ = try view.inspect().find(button: "Install voice model")
        XCTAssertThrowsError(try view.inspect().find(text: "Ready to record"))
        try view.inspect().find(button: "Finish setup").tap()
        XCTAssertEqual(openedSetup, 1)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(installs, 0)
    }

    func testConsentButtonShowsOnePendingRequestThenReadyAfterAcceptance() async throws {
        installed = true
        let session = makeSession()
        await session.refreshSetup()
        let view = RebuildModelsView(session: session)
        try view.inspect().find(button: "Allow microphone").tap()
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(try view.inspect().find(button: "Waiting for macOS…").isDisabled())
        XCTAssertThrowsError(try view.inspect().find(button: "Waiting for macOS…").tap())
        XCTAssertEqual(requests, 1)
        permission = .authorized
        try XCTUnwrap(completion)(true)
        for _ in 0..<30 { await Task.yield() }
        _ = try view.inspect().find(text: "Ready to record")
        XCTAssertThrowsError(try view.inspect().find(button: "Allow microphone"))
        try view.inspect().find(button: "Start recording").tap()
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(session.phase, .recording)
        XCTAssertTrue(try view.inspect().find(button: "Check installation").isDisabled())
        session.cancel()
    }

    func testInstallationErrorRetryUsesTheRealButtonAndClearsTheFailure() async throws {
        permission = .authorized
        install = {
            if self.installs == 1 {
                throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download interrupted"])
            }
            self.installed = true
        }
        let session = makeSession()
        await session.refreshSetup()
        let view = RebuildModelsView(session: session)
        try view.inspect().find(button: "Install voice model").tap()
        try await waitFor { session.setupError != nil && !session.isInstalling }
        _ = try view.inspect().find(text: "Download interrupted")
        try view.inspect().find(button: "Try again").tap()
        try await waitFor { self.installs == 2 && session.readiness.ready && !session.isInstalling }
        _ = try view.inspect().find(text: "Installed on this Mac")
        _ = try view.inspect().find(text: "Ready to record")
        XCTAssertThrowsError(try view.inspect().find(button: "Try again"))
    }

    func testPendingInstallationDisablesRecordingAndModelSelection() async throws {
        permission = .authorized
        var pending: CheckedContinuation<Void, Never>?
        install = { await withCheckedContinuation { pending = $0 }; self.installed = true }
        let session = makeSession()
        await session.refreshSetup()
        let view = RebuildModelsView(session: session)
        try view.inspect().find(button: "Install voice model").tap()
        try await waitFor { pending != nil }
        _ = try view.inspect().find(text: "Installing voice model…")
        XCTAssertTrue(try view.inspect().find(button: "Installing…").isDisabled())
        for picker in try view.inspect().findAll(ViewType.Picker.self) { XCTAssertTrue(try picker.isDisabled()) }
        try XCTUnwrap(pending).resume()
        try await waitFor { !session.isInstalling }
        XCTAssertEqual(installs, 1)
        XCTAssertEqual(starts, 0)
    }

    func testParakeetSelectionOffersEnglishAndMultilingualChoicesWithoutClaimingRuntimeReady() async throws {
        let session = makeSession()
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.selectedParakeetModel = .v2English
        permission = .authorized
        installed = true
        runtime = false
        await session.refreshSetup()
        let view = RebuildModelsView(session: session)
        _ = try view.inspect().find(text: "v2 English · recommended")
        _ = try view.inspect().find(text: "v3 · 25 languages")
        _ = try view.inspect().find(text: "Local runtime needed")
        _ = try view.inspect().find(button: "Install runtime & voice model")
        XCTAssertThrowsError(try view.inspect().find(text: "Ready to record"))
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition(), "Setup action did not publish the required state")
    }
}
