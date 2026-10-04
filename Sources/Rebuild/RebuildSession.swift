import AppKit
import Observation

enum RebuildPhase: Equatable {
    case idle, recording, transcribing, completed, failed

    var isBusy: Bool { self == .recording || self == .transcribing }
    var title: String {
        switch self {
        case .idle: return "Your words, made useful."
        case .recording: return "Listening."
        case .transcribing: return "Turning speech into text."
        case .completed: return "Copied to your clipboard."
        case .failed: return "Let’s try that again."
        }
    }
}

struct RebuildReadiness: Equatable {
    var microphoneGranted = false
    var modelInstalled = false
    var runtimeReady = false
    var checking = true
    var modelVerificationFailed = false
    var ready: Bool { !checking && microphoneGranted && modelInstalled && runtimeReady && !modelVerificationFailed }
    var nextStep: String {
        if checking { return "Checking your recording setup" }
        if !microphoneGranted { return "Allow microphone access" }
        if !runtimeReady { return "Install the local runtime" }
        if !modelInstalled { return "Install your voice model" }
        if modelVerificationFailed { return "Repair or verify your voice model" }
        return "Ready to record"
    }
}

@MainActor
struct RebuildSessionServices {
    var start: (UUID) -> Bool
    var stop: () -> URL?
    var cancel: () -> Void
    var transcribe: (URL, TranscriptionPipelineConfig, UUID) async throws -> TranscriptionResult
    var copy: (String) -> Void
    var save: (String, TranscriptionPipelineConfig, TimeInterval?) async throws -> Void
    var interruptionSource: NSObject?
    var startError: () -> String? = { nil }

    static func live(recorder: AudioEngineRecorder) -> Self {
        let pipeline = TranscriptionPipeline()
        return Self(
            start: { id in
                PermissionManager.shared.checkPermissionState()
                return recorder.startRecording(sessionID: id)
            }, stop: { recorder.stopRecording() },
            cancel: { recorder.cancelRecording() },
            transcribe: { url, config, id in
                try await TranscriptionProgress.$sessionID.withValue(id) {
                    try await TranscriptionProgress.$pipelineConfig.withValue(config) {
                        try await pipeline.transcribe(audioURL: url, config: config)
                    }
                }
            },
            copy: PasteManager.copyToClipboard,
            save: { text, config, duration in
                let count = UsageMetricsStore.estimatedWordCount(for: text)
                UsageMetricsStore.shared.recordSession(duration: duration, wordCount: count, characterCount: text.count)
                guard AppDefaults.transcriptionHistoryEnabled else { return }
                try await DataManager.shared.saveTranscription(
                    TranscriptionRecord(
                        text: text, provider: config.provider, duration: duration,
                        modelUsed: config.provider == .local
                            ? config.whisperModel?.rawValue : config.parakeetModel?.rawValue,
                        wordCount: count, characterCount: text.count, sourceAppBundleId: config.sourceAppBundleId
                    ))
            },
            interruptionSource: recorder,
            startError: { recorder.lastStartError }
        )
    }
}

/// The rebuild has one owner for a recording or file job. Views never record,
/// request permissions, transcribe, or paste independently.
@MainActor
@Observable
final class RebuildSession {
    private(set) var phase: RebuildPhase = .idle
    var readiness = RebuildReadiness()
    var transcript = ""
    var notice: String?
    var setupError: String?
    private(set) var isInstalling = false
    var maintenanceInProgress = false
    private(set) var isRequestingMicrophone = false
    private(set) var isVerifyingVoiceModel = false
    private(set) var verificationMessage: String?
    private(set) var duration: TimeInterval?
    var hasRetryAudio: Bool { phase == .failed && retryAudio != nil }
    var canRetry: Bool { hasRetryAudio && retryBlockedReason == nil }
    var openSetup: () -> Void = {}
    var showRecorder: () -> Void = {}
    var closeRecorder: () -> Void = {}
    var didDeliver: () -> Void = {}
    @ObservationIgnored private let services: RebuildSessionServices
    @ObservationIgnored private let setup: RebuildSetupServices
    @ObservationIgnored private let verificationStore: RebuildModelVerificationStore
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var configuration: TranscriptionPipelineConfig?
    @ObservationIgnored private var capturedTarget: NSRunningApplication?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var refreshInFlight = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private let paste = PasteManager()
    @ObservationIgnored private var retryAudio: RetryAudio?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var verificationSelection: RebuildModelSelection?
    @ObservationIgnored private var verificationAssets: String?

    private struct RetryAudio {
        let url: URL
        let config: TranscriptionPipelineConfig
        let owned: Bool
        let duration: TimeInterval?
    }

    func selectionChanged() {
        readiness.checking = true
        verificationMessage = nil
        Task { await refreshSetup() }
    }

    func retry() {
        guard hasRetryAudio, let audio = retryAudio else { return }
        guard retryBlockedReason == nil else {
            notice = retryBlockedReason
            return
        }
        retryAudio = nil
        sessionID = UUID()
        notice = nil
        duration = audio.duration
        guard let id = sessionID else { return }
        transcribe(url: audio.url, config: audio.config, id: id, removeAfterward: audio.owned)
    }

    private func discardRetry() {
        if let audio = retryAudio, audio.owned { try? FileManager.default.removeItem(at: audio.url) }
        retryAudio = nil
    }

    init(
        services: RebuildSessionServices, setup: RebuildSetupServices? = nil,
        verificationDefaults: UserDefaults? = nil
    ) {
        self.services = services
        self.setup = setup ?? .live
        self.verificationStore = RebuildModelVerificationStore(defaults: verificationDefaults ?? AppDefaults.defaults)
        if let source = services.interruptionSource {
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: .recordingInterrupted, object: source, queue: nil
            ) { [weak self] notification in
                guard let event = notification.userInfo?["event"] as? RecordingInterruption else { return }
                MainActor.assumeIsolated { self?.handleInterruption(event) }
            }
        }
    }

    deinit {
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    private func handleInterruption(_ event: RecordingInterruption) {
        guard event.sessionID == sessionID else {
            if case .finished(_, let audio?, _) = event { try? FileManager.default.removeItem(at: audio) }
            return
        }
        // A duplicate stop event must not delete audio already in transcription.
        guard phase == .recording, let config = configuration else { return }
        closeRecorder()
        switch event {
        case .finished(let id, let audio?, let capturedDuration):
            duration = capturedDuration
            notice = "Recording was interrupted. Transcribing the audio captured before it stopped."
            transcribe(url: audio, config: config, id: id, removeAfterward: true)
        case .finished:
            phase = .failed
            notice = "Recording was interrupted before usable audio was captured. Try again."
            sessionID = nil
        case .failed(_, let message):
            phase = .failed
            notice = message
            sessionID = nil
        }
    }

    func toggleRecording() {
        if phase == .recording {
            finishRecording()
            return
        }
        guard phase != .transcribing else { return }
        guard readiness.ready, !isInstalling, !maintenanceInProgress else {
            openSetup()
            return
        }
        prepareSession()
        guard let id = sessionID, services.start(id) else {
            phase = .failed
            notice = services.startError() ?? "The microphone could not start. Check the selected input and try again."
            sessionID = nil
            return
        }
        startedAt = Date()
        phase = .recording
        if !AppDefaults.immediateRecording { showRecorder() }
    }

    func finishRecording() {
        guard phase == .recording, let id = sessionID, let config = configuration else { return }
        duration = startedAt.map { Date().timeIntervalSince($0) }
        guard let url = services.stop() else {
            phase = .failed
            notice = "No audio was captured. Try a different microphone."
            sessionID = nil
            closeRecorder()
            return
        }
        transcribe(url: url, config: config, id: id, removeAfterward: true)
    }

    func importAudio(_ url: URL) {
        guard canImportAudio else {
            notice = fileBlockedReason
            if phase.isBusy || isInstalling || maintenanceInProgress { return }
            openSetup()
            return
        }
        prepareSession()
        guard let id = sessionID, let config = configuration else { return }
        duration = nil
        transcribe(url: url, config: config, id: id, removeAfterward: false)
    }

    private func prepareSession() {
        discardRetry()
        duration = nil
        let front = NSWorkspace.shared.frontmostApplication
        capturedTarget = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
        sessionID = UUID()
        notice = nil
        configuration = TranscriptionPipelineConfig(
            provider: AppDefaults.transcriptionProvider, whisperModel: AppDefaults.selectedWhisperModel,
            applySemanticCorrection: AppDefaults.semanticCorrectionMode != .off,
            sourceAppBundleId: capturedTarget?.bundleIdentifier, parakeetModel: AppDefaults.selectedParakeetModel,
            correctionMode: AppDefaults.semanticCorrectionMode,
            correctionModelRepo: AppDefaults.semanticCorrectionModelRepo
        )
    }

    private func transcribe(url: URL, config: TranscriptionPipelineConfig, id: UUID, removeAfterward: Bool) {
        phase = .transcribing
        job = Task { [weak self] in
            guard let self else { return }
            var retainedForRetry = false
            defer { if removeAfterward && !retainedForRetry { try? FileManager.default.removeItem(at: url) } }
            do {
                let result = try await services.transcribe(url, config, id)
                guard !Task.isCancelled, sessionID == id else { return }
                guard !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NSError(
                        domain: "AudioWhisper", code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "No speech was recognized. Try again or record clearer audio."
                        ])
                }
                transcript = result.text
                services.copy(result.text)
                if case .failed = result.correctionOutcome {
                    notice = "Copied the original transcript. Writing cleanup was unavailable."
                }
                do { try await services.save(result.text, config, duration) } catch {
                    notice = "Copied your transcript, but history could not be saved: \(error.localizedDescription)"
                }
                guard !Task.isCancelled, sessionID == id else { return }
                phase = .completed
                closeRecorder()
                didDeliver()
                if AppDefaults.playCompletionSound { NSSound(named: "Pop")?.play() }
                if AppDefaults.enableSmartPaste, let target = capturedTarget, !target.isTerminated {
                    target.activate()
                    paste.pasteWithUserInteraction(
                        expectedTargetPID: target.processIdentifier,
                        isSessionValid: { [weak self] in
                            self?.sessionID == id
                        },
                        completion: { [weak self] result in
                            guard self?.sessionID == id else { return }
                            if case .failure = result { self?.notice = "Copied. Paste manually with Command V." }
                        }
                    )
                }
            } catch {
                guard sessionID == id, !Task.isCancelled else { return }
                retryAudio = RetryAudio(url: url, config: config, owned: removeAfterward, duration: duration)
                retainedForRetry = true
                phase = .failed
                notice = error.localizedDescription
                closeRecorder()
            }
        }
    }

    func cancel() {
        discardRetry()
        sessionID = nil
        job?.cancel()
        job = nil
        services.cancel()
        phase = .idle
        notice = nil
        closeRecorder()
    }
}

extension RebuildSession {
    var canImportAudio: Bool { fileBlockedReason == nil }

    var fileBlockedReason: String? {
        if phase == .recording { return "Finish or cancel the recording first." }
        if phase == .transcribing { return "Wait for transcription or cancel it first." }
        if isInstalling { return "Wait for the voice model installation to finish." }
        if maintenanceInProgress { return "Wait for model verification or maintenance to finish." }
        if readiness.checking { return "Wait for the setup check to finish." }
        if !readiness.runtimeReady { return "Install the local runtime in Voice Models." }
        if !readiness.modelInstalled { return "Install your voice model in Voice Models." }
        if readiness.modelVerificationFailed { return "Repair or verify your voice model in Voice Models." }
        return nil
    }

    var retryBlockedReason: String? {
        if let reason = fileBlockedReason { return reason }
        guard let config = retryAudio?.config else { return nil }
        let selected = setup.selection()
        let sameModel = config.provider == selected.provider && (
            config.provider == .local ? config.whisperModel == selected.whisper : config.parakeetModel == selected.parakeet)
        return sameModel ? nil : "Select the voice model used for this recording before retrying."
    }

    func verifyVoiceModel() async {
        guard !phase.isBusy, !isInstalling, !maintenanceInProgress else { return }
        isVerifyingVoiceModel = true
        maintenanceInProgress = true
        verificationMessage = nil
        defer {
            isVerifyingVoiceModel = false
            maintenanceInProgress = false
        }
        let selection = setup.selection()
        let assets = await setup.assetIdentity(selection)
        guard !Task.isCancelled, selection == setup.selection() else { return }
        let result: ModelVerificationResult
        do {
            result = try await setup.verify(selection)
        } catch {
            result = ModelVerificationResult(succeeded: false, message: "Verification failed: \(error.localizedDescription)")
        }
        let currentAssets = await setup.assetIdentity(selection)
        guard !Task.isCancelled, selection == setup.selection(), assets == currentAssets else {
            await refreshSetup()
            return
        }
        verificationStore.record(result, for: selection, assets: assets)
        verificationSelection = selection
        verificationAssets = assets
        verificationMessage = result.message
        await refreshSetup()
    }

    func refreshSetup() async {
        refreshAgain = true
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        while refreshAgain {
            refreshAgain = false
            let selection = setup.selection()
            let runtime = await setup.runtimeReady(selection)
            let installed = await setup.modelInstalled(selection)
            let assets = await setup.assetIdentity(selection)
            guard selection == setup.selection() else {
                refreshAgain = true
                continue
            }
            let failure = verificationStore.failure(for: selection, assets: assets)
            if verificationSelection != selection || verificationAssets != assets { verificationMessage = nil }
            if let failure {
                verificationSelection = selection
                verificationAssets = assets
                verificationMessage = failure
            }
            readiness = RebuildReadiness(
                microphoneGranted: setup.microphoneStatus() == .authorized,
                modelInstalled: installed, runtimeReady: runtime, checking: false,
                modelVerificationFailed: failure != nil
            )
        }
    }

    func requestMicrophone() {
        guard !isRequestingMicrophone else { return }
        switch setup.microphoneStatus() {
        case .notDetermined:
            isRequestingMicrophone = true
            setup.requestMicrophone { [weak self] _ in
                Task { @MainActor in
                    self?.isRequestingMicrophone = false
                    await self?.refreshSetup()
                }
            }
        case .denied, .restricted:
            setup.openMicrophoneSettings()
        default: Task { await refreshSetup() }
        }
    }

    func installVoiceModel() async {
        guard !isInstalling, !phase.isBusy, !maintenanceInProgress else { return }
        isInstalling = true
        setupError = nil
        defer { isInstalling = false }
        let selection = setup.selection()
        do {
            try await setup.install(selection)
        } catch { setupError = error.localizedDescription }
        await refreshSetup()
    }

}
