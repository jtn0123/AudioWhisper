import XCTest
@testable import AudioWhisper

@MainActor
final class RecordingSetupTests: IsolatedXCTestCase {
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    func testAnotherInstalledWhisperModelDoesNotMakeTheSelectedModelReady() {
        let requirement = modelRequirement(downloaded: [.tiny])
        XCTAssertEqual(requirement, .whisperModel(.base))
        XCTAssertFalse(requirement.isReady)
    }

    func testSelectedWhisperModelAndMicrophoneAreBothRequired() {
        let model = modelRequirement(downloaded: [.base])
        XCTAssertEqual(RecordingSetupRequirement.assess(microphone: .granted, modelRequirement: model), .ready)
        XCTAssertEqual(RecordingSetupRequirement.assess(microphone: .notRequested, modelRequirement: model), .microphone)
        XCTAssertEqual(RecordingSetupRequirement.assess(microphone: .requesting, modelRequirement: model), .microphoneRequesting)
        XCTAssertEqual(RecordingSetupRequirement.assess(microphone: .denied, modelRequirement: model), .microphoneDenied)
        XCTAssertEqual(RecordingSetupRequirement.assess(microphone: .restricted, modelRequirement: model), .microphoneRestricted)
    }

    func testParakeetEnvironmentWithoutSelectedModelIsNotReady() {
        XCTAssertEqual(modelRequirement(provider: .parakeet, environment: true), .parakeetModel(.v3Multilingual))
    }

    func testParakeetWaitsForEnvironmentCheckAndSupportsOnlyCompatibleHardware() {
        XCTAssertEqual(modelRequirement(provider: .parakeet, environment: nil), .checking)
        XCTAssertEqual(modelRequirement(provider: .parakeet, environment: false), .parakeetEnvironment)
        XCTAssertEqual(modelRequirement(provider: .parakeet, environment: true, cached: true), .ready)
        XCTAssertEqual(modelRequirement(provider: .parakeet, supportsParakeet: false), .unsupportedHardware)
    }

    func testMenuDoesNotSayReadyWhenSetupIsIncomplete() {
        let header = MenuHeaderView(providerRaw: "local", todayWPM: 80, readiness: .whisperModel(.base))
        XCTAssertEqual(header.statusLine, "Download Base (142MB) to record")
        XCTAssertFalse(header.statusLine.contains("Ready"))
    }

    func testRecordingStatusDoesNotSayReadyWhenTheModelIsMissing() {
        let status = StatusViewModel()
        status.updateStatus(
            isRecording: false, isProcessing: false, progressMessage: "", hasPermission: true,
            showSuccess: false, setupMessage: "Download Base to record"
        )
        XCTAssertEqual(status.currentStatus, .setupRequired("Download Base to record"))
    }

    func testViewModelRoutesMissingModelToSetupWithoutStartingMicrophoneOrShowingError() {
        let recorder = MockAudioEngineRecorder()
        let permission = PermissionManager()
        permission.microphonePermissionState = .granted
        let viewModel = makeViewModel()
        var setupRequests = 0

        for _ in 0..<5 {
            viewModel.startRecording(
                audioRecorder: recorder, permissionManager: permission,
                setupRequirement: .whisperModel(.base), presentSetup: { setupRequests += 1 }
            )
        }

        XCTAssertEqual(recorder.startRecordingCallCount, 0)
        XCTAssertEqual(setupRequests, 5, "Every attempt routes to the same existing setup window")
        XCTAssertFalse(viewModel.showError)
        XCTAssertFalse(permission.showEducationalModal)
        XCTAssertFalse(permission.showRecoveryModal)
    }

    func testViewModelDoesNotAskForPermissionFromTheRecordingShortcut() {
        let recorder = MockAudioEngineRecorder()
        let permission = PermissionManager()
        permission.microphonePermissionState = .notRequested
        let viewModel = makeViewModel()
        var setupRequests = 0
        viewModel.startRecording(
            audioRecorder: recorder, permissionManager: permission,
            setupRequirement: .microphone, presentSetup: { setupRequests += 1 }
        )
        XCTAssertEqual(setupRequests, 1)
        XCTAssertEqual(recorder.startRecordingCallCount, 0)
        XCTAssertFalse(permission.showEducationalModal)
    }

    func testReadyViewModelStartsRecording() {
        let recorder = MockAudioEngineRecorder()
        let permission = PermissionManager()
        permission.microphonePermissionState = .granted
        let viewModel = makeViewModel()
        viewModel.startRecording(
            audioRecorder: recorder, permissionManager: permission,
            setupRequirement: .ready, presentSetup: { XCTFail("Ready recordings must not open setup") }
        )
        XCTAssertEqual(recorder.startRecordingCallCount, 1)
    }

    func testChangingParakeetSelectionWhileCheckingRefreshesTheLatestModel() async throws {
        let original = AppDefaults.selectedParakeetModel
        defer { AppDefaults.selectedParakeetModel = original }
        AppDefaults.selectedParakeetModel = .v2English
        var response: CheckedContinuation<Bool, Never>?
        var checkedModels: [ParakeetModel] = []
        var environmentChecks = 0
        let state = RecordingSetupState(
            environmentCheck: {
                environmentChecks += 1
                if environmentChecks == 1 {
                    return await withCheckedContinuation { response = $0 }
                }
                return true
            },
            cacheCheck: { model in checkedModels.append(model); return true }
        )
        let refresh = Task { await state.refresh() }
        let deadline = ContinuousClock.now + .seconds(2)
        while response == nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard let response else {
            refresh.cancel()
            return XCTFail("Setup check should reach its held environment response")
        }
        AppDefaults.selectedParakeetModel = .v3Multilingual
        await state.refresh()
        response.resume(returning: true)
        await refresh.value
        XCTAssertEqual(checkedModels, [.v2English, .v3Multilingual])
        XCTAssertEqual(state.cachedParakeetModel, .v3Multilingual)
        XCTAssertEqual(state.environmentReady, true)
        XCTAssertFalse(state.isRefreshing)
    }

    private func modelRequirement(
        provider: TranscriptionProvider = .local,
        downloaded: Set<WhisperModel> = [],
        environment: Bool? = nil,
        cached: Bool = false,
        supportsParakeet: Bool = true
    ) -> RecordingSetupRequirement {
        RecordingSetupRequirement.modelRequirement(RecordingSetupInputs(
            provider: provider, whisperModel: .base, downloadedWhisperModels: downloaded,
            parakeetModel: .v3Multilingual, environmentReady: environment,
            parakeetModelCached: cached, supportsParakeet: supportsParakeet
        ))
    }

    private func makeViewModel() -> RecordingViewModel {
        RecordingViewModel(
            speechService: SpeechToTextService(), pasteManager: PasteManager(),
            semanticCorrectionService: SemanticCorrectionService(), soundManager: SoundManager(),
            statusViewModel: StatusViewModel()
        )
    }
}
