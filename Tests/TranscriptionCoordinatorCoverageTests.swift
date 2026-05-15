import XCTest
@testable import AudioWhisper

/// Coverage tests for `TranscriptionCoordinator`, `TranscriptionRunContext`,
/// and the error-mapping / correction-failure tail.
@MainActor
final class TranscriptionCoordinatorCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): exercises code that reads AppDefaults (semanticCorrectionMode,
    // enableSmartPaste) backed by UserDefaults.standard.
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

    private func makeContext(
        source: TranscriptionSource = .liveRecording(sessionDuration: 1.0),
        provider: TranscriptionProvider = .parakeet,
        hint: Bool = false,
        setHintShown: @escaping () -> Void = {}
    ) -> TranscriptionRunContext {
        TranscriptionRunContext(
            source: source,
            transcriptionProvider: provider,
            selectedWhisperModel: .base,
            shouldHintThisRun: hint,
            setHintShown: setHintShown
        )
    }

    // MARK: - TranscriptionRunContext

    func testRunContextHoldsValues() {
        var hintCalled = false
        let ctx = makeContext(provider: .local, hint: true) { hintCalled = true }
        XCTAssertEqual(ctx.transcriptionProvider, .local)
        XCTAssertEqual(ctx.selectedWhisperModel, .base)
        XCTAssertTrue(ctx.shouldHintThisRun)
        ctx.setHintShown()
        XCTAssertTrue(hintCalled)
    }

    // MARK: - TranscriptionSource

    func testTranscriptionSourceDurationLiveRecording() {
        let source = TranscriptionSource.liveRecording(sessionDuration: 12.5)
        XCTAssertEqual(source.duration, 12.5)
    }

    func testTranscriptionSourceDurationImportedFile() {
        let url = URL(fileURLWithPath: "/tmp/x.m4a")
        let source = TranscriptionSource.importedFile(url, estimatedDuration: 7.0)
        XCTAssertEqual(source.duration, 7.0)
    }

    func testTranscriptionSourceDurationLiveNil() {
        let source = TranscriptionSource.liveRecording(sessionDuration: nil)
        XCTAssertNil(source.duration)
    }

    func testDashboardReasonAllCombinations() {
        let live = TranscriptionSource.liveRecording(sessionDuration: 1)
        let file = TranscriptionSource.importedFile(URL(fileURLWithPath: "/tmp/a.m4a"), estimatedDuration: 1)
        XCTAssertEqual(live.dashboardReason(for: .local), "liveLocalModelMissing")
        XCTAssertEqual(live.dashboardReason(for: .parakeet), "liveParakeetModelMissing")
        XCTAssertEqual(file.dashboardReason(for: .local), "fileLocalModelMissing")
        XCTAssertEqual(file.dashboardReason(for: .parakeet), "fileParakeetModelMissing")
    }

    // MARK: - Coordinator construction

    func testCoordinatorConvenienceInitWiresPipeline() {
        let coordinator = TranscriptionCoordinator(
            speechService: SpeechToTextService(),
            correctionService: SemanticCorrectionService()
        )
        XCTAssertNil(coordinator.viewModel)
    }

    func testViewModelWiresCoordinatorBackReference() {
        let vm = makeViewModel()
        XCTAssertTrue(vm.coordinator.viewModel === vm)
    }

    // MARK: - finishTranscription tail

    func testFinishTranscriptionWithNilViewModelIsNoOp() async {
        let coordinator = TranscriptionCoordinator(
            speechService: SpeechToTextService(),
            correctionService: SemanticCorrectionService()
        )
        // viewModel is weak + nil — should return without crashing.
        await coordinator.finishTranscription(text: "hello", context: makeContext())
    }

    func testFinishTranscriptionSetsSuccessAndClearsStartTime() async {
        let vm = makeViewModel()
        vm.transcriptionStartTime = Date()
        await vm.coordinator.finishTranscription(
            text: "Some transcribed text",
            context: makeContext()
        )
        XCTAssertTrue(vm.showSuccess)
        XCTAssertFalse(vm.isProcessing)
        XCTAssertNil(vm.transcriptionStartTime)
    }

    func testFinishTranscriptionAdvancesHintFlag() async {
        let vm = makeViewModel()
        vm.showFirstModelUseHint = true
        var hintShown = false
        await vm.coordinator.finishTranscription(
            text: "text",
            context: makeContext(hint: true) { hintShown = true }
        )
        XCTAssertTrue(hintShown)
        XCTAssertFalse(vm.showFirstModelUseHint)
    }

    func testFinishTranscriptionWithFailedCorrectionShowsBanner() async {
        let vm = makeViewModel()
        let err = NSError(domain: "MLX", code: 1)
        await vm.coordinator.finishTranscription(
            text: "raw text",
            correctionOutcome: .failed(err, fallback: "raw text"),
            context: makeContext()
        )
        XCTAssertEqual(vm.correctionFailedMessage, "Correction failed; raw transcript copied")
    }

    func testFinishTranscriptionWithAppliedCorrectionNoBanner() async {
        let vm = makeViewModel()
        await vm.coordinator.finishTranscription(
            text: "corrected text",
            correctionOutcome: .applied("corrected text"),
            context: makeContext()
        )
        XCTAssertNil(vm.correctionFailedMessage)
    }

    func testFinishTranscriptionLocalProviderRecordsModel() async {
        let vm = makeViewModel()
        await vm.coordinator.finishTranscription(
            text: "local provider text",
            context: makeContext(provider: .local)
        )
        XCTAssertTrue(vm.showSuccess)
    }

    // MARK: - handleTranscriptionError mapping

    func testHandleErrorGenericSetsErrorMessage() {
        let vm = makeViewModel()
        let err = NSError(domain: "Test", code: 9, userInfo: [NSLocalizedDescriptionKey: "boom"])
        vm.coordinator.handleTranscriptionError(
            err,
            source: .liveRecording(sessionDuration: 1),
            transcriptionProvider: .parakeet,
            shouldHintThisRun: false,
            setHintShown: {}
        )
        XCTAssertTrue(vm.showError)
        XCTAssertEqual(vm.errorMessage, "boom")
        XCTAssertFalse(vm.isProcessing)
        XCTAssertNil(vm.transcriptionStartTime)
    }

    func testHandleErrorModelNotDownloadedRoutesToDashboard() {
        let vm = makeViewModel()
        var reason: String?
        let inner = SpeechToTextError.localTranscriptionFailed(LocalWhisperError.modelNotDownloaded)
        vm.coordinator.handleTranscriptionError(
            inner,
            source: .liveRecording(sessionDuration: 1),
            transcriptionProvider: .local,
            shouldHintThisRun: false,
            setHintShown: {},
            presentDashboard: { reason = $0 }
        )
        XCTAssertTrue(vm.showError)
        XCTAssertTrue(vm.errorMessage.contains("Local Whisper model not downloaded"))
        XCTAssertEqual(reason, "liveLocalModelMissing")
    }

    func testHandleErrorParakeetModelNotReadyRoutesToDashboard() {
        let vm = makeViewModel()
        var reason: String?
        vm.coordinator.handleTranscriptionError(
            ParakeetError.modelNotReady,
            source: .importedFile(URL(fileURLWithPath: "/tmp/a.m4a"), estimatedDuration: 1),
            transcriptionProvider: .parakeet,
            shouldHintThisRun: false,
            setHintShown: {},
            presentDashboard: { reason = $0 }
        )
        XCTAssertTrue(vm.errorMessage.contains("Parakeet model not downloaded"))
        XCTAssertEqual(reason, "fileParakeetModelMissing")
    }

    func testHandleErrorAdvancesHintFlag() {
        let vm = makeViewModel()
        vm.showFirstModelUseHint = true
        var hintShown = false
        vm.coordinator.handleTranscriptionError(
            NSError(domain: "T", code: 1),
            source: .liveRecording(sessionDuration: 1),
            transcriptionProvider: .parakeet,
            shouldHintThisRun: true,
            setHintShown: { hintShown = true }
        )
        XCTAssertTrue(hintShown)
        XCTAssertFalse(vm.showFirstModelUseHint)
    }

    func testHandleErrorWithNilViewModelIsNoOp() {
        let coordinator = TranscriptionCoordinator(
            speechService: SpeechToTextService(),
            correctionService: SemanticCorrectionService()
        )
        coordinator.handleTranscriptionError(
            NSError(domain: "T", code: 1),
            source: .liveRecording(sessionDuration: 1),
            transcriptionProvider: .parakeet,
            shouldHintThisRun: false,
            setHintShown: {}
        )
        // No crash expected.
    }

    // MARK: - runTranscription pass-through

    func testRunTranscriptionFailsForInvalidAudio() async {
        let vm = makeViewModel()
        let badURL = URL(fileURLWithPath: "/nonexistent/audio.m4a")
        let config = TranscriptionPipelineConfig(provider: .parakeet)
        do {
            _ = try await vm.coordinator.runTranscription(audioURL: badURL, config: config)
            XCTFail("Expected failure for invalid audio")
        } catch {
            XCTAssertTrue(error is SpeechToTextError)
        }
    }
}
