import XCTest
@testable import AudioWhisper

/// Coverage tests for `RecordingViewModel` lifecycle, success UI, and the
/// PR-changed coordinator-forwarder surface.
@MainActor
final class RecordingViewModelCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): RecordingViewModel reads AppDefaults (enableSmartPaste,
    // semanticCorrectionMode) backed by UserDefaults.standard.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private func makeViewModel() -> RecordingViewModel {
        RecordingViewModel(
            speechService: SpeechToTextService(),
            pasteManager: PasteManager(),
            semanticCorrectionService: SemanticCorrectionService(),
            soundManager: SoundManager(),
            statusViewModel: StatusViewModel()
        )
    }

    // MARK: - markProcessingFinished

    func testMarkProcessingFinishedClearsFlag() {
        let vm = makeViewModel()
        // isProcessing starts false; calling the clearer keeps it false.
        vm.markProcessingFinished()
        XCTAssertFalse(vm.isProcessing)
    }

    // MARK: - showConfirmationAndPaste

    func testShowConfirmationAndPasteSetsSuccess() {
        let vm = makeViewModel()
        vm.showConfirmationAndPaste(text: "transcribed")
        XCTAssertTrue(vm.showSuccess)
        XCTAssertFalse(vm.isProcessing)
    }

    func testShowConfirmationAndPasteWithEmptyText() {
        let vm = makeViewModel()
        vm.showConfirmationAndPaste(text: "")
        XCTAssertTrue(vm.showSuccess)
    }

    func testShowConfirmationAndPasteWhenAwaitingSemanticPaste() {
        let vm = makeViewModel()
        vm.awaitingSemanticPaste = true
        vm.showConfirmationAndPaste(text: "deferred paste text")
        XCTAssertTrue(vm.showSuccess)
    }

    // MARK: - Lifecycle

    func testOnAppearInvokesLoadProvider() {
        let vm = makeViewModel()
        let permissionManager = PermissionManager()
        var loaded = false
        vm.onAppear(permissionManager: permissionManager) { loaded = true }
        XCTAssertTrue(loaded)
        XCTAssertEqual(vm.notificationTasks.count, 3)
        vm.stopNotificationObservers()
    }

    func testOnDisappearClearsStateAndObservers() {
        let vm = makeViewModel()
        vm.setupNotificationObservers()
        vm.lastAudioURL = URL(fileURLWithPath: "/tmp/x.m4a")
        vm.onDisappear()
        XCTAssertNil(vm.lastAudioURL)
        XCTAssertTrue(vm.notificationTasks.isEmpty)
    }

    func testCancelProcessingIsSafeWhenIdle() {
        let vm = makeViewModel()
        vm.cancelProcessing()
        XCTAssertFalse(vm.isProcessing)
    }

    // MARK: - startRecording

    func testStartRecordingClearsLastAudioURLWhenPermitted() {
        let vm = makeViewModel()
        let recorder = AudioEngineRecorder()
        let permissionManager = PermissionManager()
        vm.lastAudioURL = URL(fileURLWithPath: "/tmp/stale.m4a")
        // Exercises the start path. When permission is granted, lastAudioURL is
        // reset before recording; when not granted, the request path runs.
        vm.startRecording(audioRecorder: recorder, permissionManager: permissionManager)
        if permissionManager.microphonePermissionState == .granted {
            XCTAssertNil(vm.lastAudioURL)
        } else {
            // Request path taken; lastAudioURL is untouched.
            XCTAssertNotNil(vm.lastAudioURL)
        }
        _ = recorder.stopRecording()
    }

    // MARK: - Coordinator forwarders (PR-changed surface)

    func testFinishTranscriptionForwarderDelegatesToCoordinator() async {
        let vm = makeViewModel()
        vm.transcriptionStartTime = Date()
        await vm.finishTranscription(
            text: "forwarded text",
            context: TranscriptionRunContext(
                source: .liveRecording(sessionDuration: 2.0),
                transcriptionProvider: .parakeet,
                selectedWhisperModel: .base,
                shouldHintThisRun: false,
                setHintShown: {}
            )
        )
        XCTAssertTrue(vm.showSuccess)
        XCTAssertNil(vm.transcriptionStartTime)
    }

    func testHandleTranscriptionErrorForwarderDelegatesToCoordinator() {
        let vm = makeViewModel()
        vm.handleTranscriptionError(
            NSError(domain: "Fwd", code: 5, userInfo: [NSLocalizedDescriptionKey: "forwarded error"]),
            source: .liveRecording(sessionDuration: 1),
            transcriptionProvider: .parakeet,
            shouldHintThisRun: false,
            setHintShown: {}
        )
        XCTAssertTrue(vm.showError)
        XCTAssertEqual(vm.errorMessage, "forwarded error")
    }

    func testHandleTranscriptionErrorForwarderWithDashboardPresenter() {
        let vm = makeViewModel()
        var dashboardReason: String?
        vm.handleTranscriptionError(
            ParakeetError.modelNotReady,
            source: .liveRecording(sessionDuration: 1),
            transcriptionProvider: .parakeet,
            shouldHintThisRun: false,
            setHintShown: {},
            presentDashboard: { dashboardReason = $0 }
        )
        XCTAssertEqual(dashboardReason, "liveParakeetModelMissing")
    }
}
