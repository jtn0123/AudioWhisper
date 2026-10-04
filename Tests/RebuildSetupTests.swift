import AVFoundation
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildSetupTests: IsolatedXCTestCase {
    private var selection = RebuildModelSelection(provider: .local, whisper: .base, parakeet: .v3Multilingual)
    private var microphone: AVAuthorizationStatus = .notDetermined
    private var requests = 0
    private var settingsOpened = 0
    private var requestCompletion: (@Sendable (Bool) -> Void)?
    private var installed = true
    private var runtime = true
    private var installs = 0
    private var starts = 0
    private var installOperation: ((RebuildModelSelection) async throws -> Void)?
    private var runtimeOperation: ((RebuildModelSelection) async -> Bool)?

    private func makeSession() -> RebuildSession {
        RebuildSession(
            services: RebuildSessionServices(
                start: { _ in self.starts += 1; return true }, stop: { nil }, cancel: {},
                transcribe: { _, _, _ in TranscriptionResult(text: "fixture", correctionOutcome: nil) },
                copy: { _ in }, save: { _, _, _ in }),
            setup: RebuildSetupServices(
                selection: { self.selection }, microphoneStatus: { self.microphone },
                requestMicrophone: { self.requests += 1; self.requestCompletion = $0 },
                openMicrophoneSettings: { self.settingsOpened += 1 },
                runtimeReady: { selection in
                    if let operation = self.runtimeOperation { return await operation(selection) }
                    return self.runtime
                },
                modelInstalled: { _ in self.installed },
                install: { selection in
                    self.installs += 1
                    if let operation = self.installOperation { try await operation(selection) } else { self.installed = true }
                }
            ))
    }

    func testRepeatedRequestsCoalesceAndDenialDoesNotRePrompt() async throws {
        let session = makeSession()
        for _ in 0..<5 { session.requestMicrophone() }
        XCTAssertEqual(requests, 1)
        XCTAssertTrue(session.isRequestingMicrophone)
        microphone = .denied
        try XCTUnwrap(requestCompletion)(false)
        await settle()
        XCTAssertFalse(session.isRequestingMicrophone)
        XCTAssertFalse(session.readiness.ready)
        session.requestMicrophone()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(settingsOpened, 1)
    }

    func testBlockedRecordingCommandsNeverRequestConsentOrInstall() async {
        let session = makeSession()
        await session.refreshSetup()
        for _ in 0..<5 { session.toggleRecording() }
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(starts, 0)
    }

    func testAllowedConsentRefreshesAllPrerequisites() async throws {
        let session = makeSession()
        session.requestMicrophone()
        microphone = .authorized
        try XCTUnwrap(requestCompletion)(true)
        await settle()
        XCTAssertTrue(session.readiness.ready)
        XCTAssertFalse(session.isRequestingMicrophone)
    }

    func testStaleSetupCannotPublishReadinessAfterSelectionChanges() async throws {
        var pending: CheckedContinuation<Bool, Never>?
        var checked: [WhisperModel] = []
        runtimeOperation = { selection in
            checked.append(selection.whisper)
            if selection.whisper == .base { return await withCheckedContinuation { pending = $0 } }
            return false
        }
        microphone = .authorized
        let session = makeSession()
        let refresh = Task { await session.refreshSetup() }
        await settle()
        selection = RebuildModelSelection(provider: .local, whisper: .tiny, parakeet: .v3Multilingual)
        session.selectionChanged()
        XCTAssertFalse(session.readiness.ready)
        try XCTUnwrap(pending).resume(returning: true)
        await refresh.value
        await settle()
        XCTAssertEqual(checked, [.base, .tiny])
        XCTAssertFalse(session.readiness.runtimeReady)
        XCTAssertFalse(session.readiness.checking)
    }

    func testInstallationFailureRemainsActionableAndRetrySucceeds() async {
        installed = false
        microphone = .authorized
        installOperation = { _ in
            if self.installs == 1 {
                throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download interrupted"])
            }
            self.installed = true
        }
        let session = makeSession()
        await session.installVoiceModel()
        XCTAssertEqual(session.setupError, "Download interrupted")
        XCTAssertFalse(session.isInstalling)
        XCTAssertFalse(session.readiness.ready)
        await session.installVoiceModel()
        XCTAssertEqual(installs, 2)
        XCTAssertNil(session.setupError)
        XCTAssertTrue(session.readiness.ready)
    }

    func testConcurrentInstallationIsSingleFlightAndBlocksRecording() async throws {
        var pending: CheckedContinuation<Void, Never>?
        installOperation = { _ in await withCheckedContinuation { pending = $0 } }
        microphone = .authorized
        let session = makeSession()
        await session.refreshSetup()
        let installation = Task { await session.installVoiceModel() }
        await settle()
        XCTAssertTrue(session.isInstalling)
        await session.installVoiceModel()
        session.toggleRecording()
        XCTAssertEqual(installs, 1)
        XCTAssertEqual(starts, 0)
        try XCTUnwrap(pending).resume()
        await installation.value
        XCTAssertFalse(session.isInstalling)
    }

    func testMaintenanceBlocksInstallation() async {
        let session = makeSession()
        session.maintenanceInProgress = true
        await session.installVoiceModel()
        XCTAssertEqual(installs, 0)
    }

    private func settle() async { for _ in 0..<30 { await Task.yield() } }
}
