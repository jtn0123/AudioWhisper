import AVFoundation
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
    var ready: Bool { !checking && microphoneGranted && modelInstalled && runtimeReady }
    var nextStep: String {
        if checking { return "Checking your recording setup" }
        if !microphoneGranted { return "Allow microphone access" }
        if !runtimeReady { return "Install the local runtime" }
        if !modelInstalled { return "Install your voice model" }
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
            interruptionSource: recorder
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
    private(set) var duration: TimeInterval?
    var canRetry: Bool { phase == .failed && retryAudio != nil }
    var openSetup: () -> Void = {}
    var showRecorder: () -> Void = {}
    var closeRecorder: () -> Void = {}
    var didDeliver: () -> Void = {}
    @ObservationIgnored private let services: RebuildSessionServices
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

    private struct RetryAudio {
        let url: URL
        let config: TranscriptionPipelineConfig
        let owned: Bool
        let duration: TimeInterval?
    }

    func selectionChanged() {
        readiness.checking = true
        Task { await refreshSetup() }
    }

    func retry() {
        guard canRetry, let audio = retryAudio else { return }
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

    init(services: RebuildSessionServices) {
        self.services = services
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
            notice = "The microphone could not start. Check the selected input and try again."
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
        guard !phase.isBusy, !isInstalling, !maintenanceInProgress else { return }
        guard readiness.modelInstalled && readiness.runtimeReady && !readiness.checking else {
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
    func refreshSetup() async {
        refreshAgain = true
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        while refreshAgain {
            refreshAgain = false
            let provider = AppDefaults.transcriptionProvider
            let whisper = AppDefaults.selectedWhisperModel
            let parakeet = AppDefaults.selectedParakeetModel
            let runtime = provider == .local ? true : await UvBootstrap.isEnvReady()
            let installed =
                provider == .local
                ? WhisperKitStorage.isModelDownloaded(whisper)
                : await ParakeetService.shared.isModelCached(model: parakeet)
            guard provider == AppDefaults.transcriptionProvider,
                whisper == AppDefaults.selectedWhisperModel, parakeet == AppDefaults.selectedParakeetModel
            else {
                refreshAgain = true
                continue
            }
            readiness = RebuildReadiness(
                microphoneGranted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                modelInstalled: installed, runtimeReady: runtime, checking: false
            )
        }
    }

    func requestMicrophone() {
        guard !isRequestingMicrophone else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            isRequestingMicrophone = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in
                    self?.isRequestingMicrophone = false
                    await self?.refreshSetup()
                }
            }
        case .denied, .restricted:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        default: Task { await refreshSetup() }
        }
    }

    func installVoiceModel() async {
        guard !isInstalling, !phase.isBusy, !maintenanceInProgress else { return }
        isInstalling = true
        setupError = nil
        defer { isInstalling = false }
        let provider = AppDefaults.transcriptionProvider
        let whisper = AppDefaults.selectedWhisperModel
        let parakeet = AppDefaults.selectedParakeetModel
        do {
            if provider == .local {
                try await ModelManager.shared.downloadModel(whisper)
            } else {
                guard Arch.isAppleSilicon else {
                    setupError = "Parakeet needs Apple Silicon. Choose Whisper on this Mac."
                    return
                }
                _ = try await UvBootstrap.ensureVenv(forceRefresh: true)
                await MLXModelManager.shared.downloadParakeetModel(repo: parakeet.rawValue)
                guard await ParakeetService.shared.isModelCached(model: parakeet) else {
                    setupError =
                        MLXModelManager.shared.downloadProgress[parakeet.rawValue]
                        ?? "The download did not finish. Check your connection and retry."
                    return
                }
            }
        } catch { setupError = error.localizedDescription }
        await refreshSetup()
    }

}
