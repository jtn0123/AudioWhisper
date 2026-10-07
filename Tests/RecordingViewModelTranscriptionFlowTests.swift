import XCTest
@testable import AudioWhisper

/// Coverage for the app's primary user flow: record → stop → transcribe →
/// correct → paste, plus file import and retry.
///
/// Audit item D1. This flow previously had **zero** automated coverage. It lived
/// in `ContentView+Recording.swift`, an extension on a SwiftUI `View`, which
/// measured 0.0% across 440 lines — a `View` struct cannot be instantiated in a
/// test without a rendering context. A file named
/// `Tests/Views/ContentViewRecordingTests.swift` existed and passed, but every
/// case in it declared local variables and asserted on those, so the gap was
/// invisible (audit item D2; that file is deleted).
///
/// Audit item A1 moved the flow onto `RecordingViewModel`, which is what makes
/// these tests possible at all.
@MainActor
final class RecordingViewModelTranscriptionFlowTests: IsolatedXCTestCase {
    // The flow reads AppDefaults (transcriptionProvider, semanticCorrectionMode,
    // enableSmartPaste) — matching the existing RecordingViewModel suites.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var stub: StubSpeechToTextServiceForFlow!
    private var recorder: MockAudioEngineRecorder!
    private var tempFiles: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        stub = StubSpeechToTextServiceForFlow()
        recorder = MockAudioEngineRecorder()
        // Keep correction out of the picture unless a test opts in, so these
        // assertions are about the transcription flow rather than MLX.
        AppDefaults.semanticCorrectionMode = .off
        AppDefaults.transcriptionProvider = .parakeet
    }

    override func tearDown() async throws {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
        stub = nil
        recorder = nil
        try await super.tearDown()
    }

    private func makeViewModel() -> RecordingViewModel {
        RecordingViewModel(
            speechService: stub,
            pasteManager: PasteManager(),
            semanticCorrectionService: SemanticCorrectionService(),
            soundManager: SoundManager(),
            statusViewModel: StatusViewModel()
        )
    }

    /// A file that passes `AudioValidator`, which the pipeline runs as step 1.
    private func makeAudioFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow_test_\(UUID().uuidString).m4a")
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data([0x00, 0x00, 0x00, 0x20]),
            attributes: nil
        )
        tempFiles.append(url)
        return url
    }

    /// Awaits the in-flight transcription Task rather than sleeping, so these
    /// tests are deterministic instead of timing-dependent.
    private func awaitFlow(_ viewModel: RecordingViewModel) async {
        await viewModel.processingTask?.value
    }

    private func noopDashboard(_ reason: String) {}

    // NOTE: there is deliberately no assertion that the final transcript lands
    // on the clipboard. The success tail calls `PasteManager.copyToClipboard`,
    // which hardcodes `NSPasteboard.general` — a system-wide resource shared by
    // every parallel xctest process, so such a test fails whenever a sibling
    // test's transcript wins the race. (It did, on the first run of this file.)
    // Making it deterministic needs an injectable pasteboard on `PasteManager`;
    // until then clipboard delivery is an accepted coverage gap rather than a
    // flaky test.

    // MARK: - stopAndProcess: happy path

    func testStopAndProcessTranscribesRecordedAudio() async {
        let audioURL = makeAudioFile()
        recorder.stopRecordingResult = audioURL
        stub.result = .success("hello from the recorder")
        let viewModel = makeViewModel()

        viewModel.stopAndProcess(
            audioRecorder: recorder,
            hasShownFirstModelUseHint: true,
            setHintShown: {},
            presentDashboard: noopDashboard
        )
        await awaitFlow(viewModel)

        XCTAssertEqual(stub.callCount, 1, "provider must be invoked exactly once")
        XCTAssertEqual(stub.lastAudioURL, audioURL, "the recorder's file must reach the provider")
        XCTAssertEqual(viewModel.lastAudioURL, audioURL, "lastAudioURL must be retained for retry")
        XCTAssertTrue(viewModel.showSuccess, "a successful run shows the success UI")
        XCTAssertFalse(viewModel.isProcessing, "isProcessing must be cleared when the run ends")
        XCTAssertFalse(viewModel.showError)
    }

    func testStopAndProcessStopsTheRecorder() async {
        recorder.stopRecordingResult = makeAudioFile()
        let viewModel = makeViewModel()

        viewModel.stopAndProcess(
            audioRecorder: recorder,
            hasShownFirstModelUseHint: true,
            setHintShown: {},
            presentDashboard: noopDashboard
        )
        await awaitFlow(viewModel)

        XCTAssertEqual(recorder.stopRecordingCallCount, 1)
    }

    // MARK: - stopAndProcess: failure paths

    /// The recorder yielding no URL must surface an error, not transcribe.
    func testStopAndProcessWithNoRecordingURLSurfacesAnError() async {
        recorder.stopRecordingResult = nil
        let viewModel = makeViewModel()

        viewModel.stopAndProcess(
            audioRecorder: recorder,
            hasShownFirstModelUseHint: true,
            setHintShown: {},
            presentDashboard: noopDashboard
        )
        await awaitFlow(viewModel)

        XCTAssertEqual(stub.callCount, 0, "must not transcribe without an audio file")
        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.isProcessing, "isProcessing must be cleared on failure")
        XCTAssertFalse(viewModel.showSuccess)
    }

    /// A provider failure must clear the in-flight state rather than leaving the
    /// UI spinning.
    func testStopAndProcessProviderFailureClearsProcessingState() async {
        recorder.stopRecordingResult = makeAudioFile()
        stub.result = .failure(SpeechToTextError.noSpeechDetected)
        let viewModel = makeViewModel()

        viewModel.stopAndProcess(
            audioRecorder: recorder,
            hasShownFirstModelUseHint: true,
            setHintShown: {},
            presentDashboard: noopDashboard
        )
        await awaitFlow(viewModel)

        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertFalse(viewModel.showSuccess)
        XCTAssertNil(viewModel.transcriptionStartTime, "the start time must not leak past a failure")
    }

    // MARK: - Cancellation

    /// Cancelling mid-flight must clear `isProcessing` and retire the
    /// first-model-use hint — a cancelled run still counts as having offered it.
    func testCancellingMidFlightClearsStateAndRetiresTheHint() async {
        recorder.stopRecordingResult = makeAudioFile()
        stub.delay = .seconds(10)
        let viewModel = makeViewModel()
        var hintShown = false

        viewModel.stopAndProcess(
            audioRecorder: recorder,
            hasShownFirstModelUseHint: false,
            setHintShown: { hintShown = true },
            presentDashboard: noopDashboard
        )

        XCTAssertTrue(viewModel.isProcessing, "precondition: the run is in flight")

        // Capture BEFORE cancelling: `cancelProcessing()` nils `processingTask`,
        // so reading it afterwards would yield nil and the await would return
        // immediately — before the Task's cancellation handler had run.
        let inFlight = viewModel.processingTask
        viewModel.cancelProcessing()
        await inFlight?.value

        XCTAssertFalse(viewModel.isProcessing, "cancellation must clear isProcessing")
        XCTAssertNil(viewModel.transcriptionStartTime)
        XCTAssertTrue(hintShown, "a cancelled run still retires the first-model-use hint")
        XCTAssertFalse(viewModel.showFirstModelUseHint)
        XCTAssertFalse(viewModel.showSuccess, "a cancelled run must not report success")
    }

    // MARK: - File import

    func testTranscribeExternalAudioFileTranscribesTheGivenFile() async {
        let audioURL = makeAudioFile()
        stub.result = .success("imported transcript")
        let viewModel = makeViewModel()

        viewModel.transcribeExternalAudioFile(
            audioURL,
            hasShownFirstModelUseHint: true,
            setHintShown: {},
            presentDashboard: noopDashboard
        )
        await awaitFlow(viewModel)

        XCTAssertEqual(stub.callCount, 1)
        XCTAssertEqual(stub.lastAudioURL, audioURL)
        XCTAssertEqual(viewModel.lastAudioURL, audioURL)
        XCTAssertTrue(viewModel.showSuccess)
        XCTAssertEqual(recorder.stopRecordingCallCount, 0, "file import must not touch the recorder")
    }

    // MARK: - Retry

    func testRetryWithNoPreviousAudioSurfacesAnError() {
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = nil

        viewModel.retryLastTranscription()

        XCTAssertTrue(viewModel.showError)
        XCTAssertEqual(stub.callCount, 0)
        XCTAssertFalse(viewModel.isProcessing, "the guard must return before starting a run")
    }

    /// A retry whose file has since been deleted must error *and* forget the
    /// stale URL, so the next retry does not repeat the same failure.
    func testRetryWithMissingFileClearsTheStaleURL() {
        let audioURL = makeAudioFile()
        try? FileManager.default.removeItem(at: audioURL)
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = audioURL

        viewModel.retryLastTranscription()

        XCTAssertTrue(viewModel.showError)
        XCTAssertNil(viewModel.lastAudioURL, "a missing file must be forgotten")
        XCTAssertEqual(stub.callCount, 0)
    }

    func testRetryReTranscribesTheLastAudioFile() async {
        let audioURL = makeAudioFile()
        stub.result = .success("second attempt")
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = audioURL

        viewModel.retryLastTranscription()
        await awaitFlow(viewModel)

        XCTAssertEqual(stub.callCount, 1)
        XCTAssertEqual(stub.lastAudioURL, audioURL)
        XCTAssertTrue(viewModel.showSuccess)
        XCTAssertFalse(viewModel.isProcessing)
    }

    /// The `guard !isProcessing` at the top of retry — without it a user
    /// mashing retry would stack concurrent transcriptions.
    func testRetryIsIgnoredWhileAnotherRunIsInFlight() async {
        let audioURL = makeAudioFile()
        recorder.stopRecordingResult = audioURL
        stub.delay = .seconds(10)
        let viewModel = makeViewModel()
        viewModel.lastAudioURL = audioURL

        viewModel.stopAndProcess(
            audioRecorder: recorder,
            hasShownFirstModelUseHint: true,
            setHintShown: {},
            presentDashboard: noopDashboard
        )
        XCTAssertTrue(viewModel.isProcessing, "precondition: a run is in flight")

        // Assert on Task identity rather than the provider call count: the
        // in-flight Task has not necessarily reached the provider yet, so the
        // count is still 0 here and would prove nothing. If retry's
        // `guard !isProcessing` failed to hold, it would install a *new*
        // processingTask — that is the observable consequence.
        let inFlight = viewModel.processingTask
        viewModel.retryLastTranscription()

        XCTAssertEqual(viewModel.processingTask, inFlight,
                       "retry must not replace the in-flight run with a second one")
        XCTAssertFalse(viewModel.showError, "the guard returns silently, it is not an error")

        viewModel.cancelProcessing()
        await inFlight?.value
        XCTAssertLessThanOrEqual(stub.callCount, 1, "only one run may ever reach the provider")
    }

    // MARK: - Provider routing

    func testCancelledOldFailureCannotFinishNewSession() async {
        let first = makeAudioFile()
        let second = makeAudioFile()
        var continuations: [URL: CheckedContinuation<String, Error>] = [:]
        stub.handler = { url in
            try await withCheckedThrowingContinuation { continuations[url] = $0 }
        }
        let vm = makeViewModel()
        vm.transcribeExternalAudioFile(first, hasShownFirstModelUseHint: true,
                                       setHintShown: {}, presentDashboard: noopDashboard)
        while continuations[first] == nil { await Task.yield() }
        let oldTask = vm.processingTask
        vm.cancelProcessing()
        vm.transcribeExternalAudioFile(second, hasShownFirstModelUseHint: true,
                                       setHintShown: {}, presentDashboard: noopDashboard)
        while continuations[second] == nil { await Task.yield() }
        continuations[first]?.resume(throwing: SpeechToTextError.noSpeechDetected)
        await oldTask?.value
        XCTAssertTrue(vm.isProcessing, "an old failure must not finish the new session")
        XCTAssertFalse(vm.showError, "an old failure must not show an error in the new session")
        continuations[second]?.resume(returning: "new transcript")
        await vm.processingTask?.value
        XCTAssertTrue(vm.showSuccess)
    }

    func testCancellationClearsUIWithoutWaitingForProvider() async {
        let audio = makeAudioFile()
        var continuation: CheckedContinuation<String, Error>?
        stub.handler = { _ in
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        let vm = makeViewModel()
        vm.transcribeExternalAudioFile(audio, hasShownFirstModelUseHint: true,
                                       setHintShown: {}, presentDashboard: noopDashboard)
        while continuation == nil { await Task.yield() }
        let task = vm.processingTask
        vm.cancelProcessing()
        XCTAssertFalse(vm.isProcessing, "Cancel must immediately release the recording controls")
        XCTAssertNil(vm.transcriptionStartTime)
        continuation?.resume(returning: "late transcript")
        await task?.value
        XCTAssertFalse(vm.showSuccess, "late results must be discarded")
    }

    /// The flow must pass the *configured* provider through to the pipeline,
    /// not a hardcoded one.
    func testConfiguredProviderReachesTheProvider() async {
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        recorder.stopRecordingResult = makeAudioFile()
        let viewModel = makeViewModel()

        viewModel.stopAndProcess(
            audioRecorder: recorder,
            hasShownFirstModelUseHint: true,
            setHintShown: {},
            presentDashboard: noopDashboard
        )
        await awaitFlow(viewModel)

        XCTAssertEqual(stub.lastProvider, .local)
    }
}
