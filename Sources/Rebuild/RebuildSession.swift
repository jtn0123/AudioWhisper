import AppKit
import Observation

/// The rebuild has one owner for a recording or file job. Views never record,
/// request permissions, transcribe, or paste independently.
@MainActor
@Observable
final class RebuildSession {
    let writingInstaller: RebuildWritingInstaller
    let livePreview: RebuildLivePreview
    var phase: RebuildPhase = .idle {
        didSet {
            if let message = RebuildLifecycleAnnouncement.message(phase: phase, previous: oldValue, notice: notice) {
                services.announce(message)
            }
        }
    }
    var readiness = RebuildReadiness()
    var transcript = ""
    var deliveredTranscript = ""
    var isPractice = false
    var timing = RebuildSessionTiming()
    var deliveryStatus: RebuildDeliveryStatus = .none
    var effectiveMode: ResolvedDictationMode?
    var writingContext: CapturedWritingContext?
    var contextRequested = false
    var pendingHistoryWrites = 0
    @ObservationIgnored var historyTasks: [UUID: Task<String?, Never>] = [:]
    var originalTranscript: String?
    var notice: String?
    var setupError: String?
    var isInstalling = false
    var maintenanceInProgress = false
    var maintenanceLabel: String?
    @ObservationIgnored lazy var meetings = RebuildMeetingSession(dictation: self)
    var modelDeletionRequested = false
    var modelRemovalError: String?
    var isRequestingMicrophone = false
    var isVerifyingVoiceModel = false
    var verificationMessage: String?
    var duration: TimeInterval?
    var hasRetryAudio: Bool { phase == .failed && retryAudio != nil }
    var canRetry: Bool { hasRetryAudio && retryBlockedReason == nil }
    var openSetup: () -> Void = {}
    var showRecorder: () -> Void = {}
    var closeRecorder: () -> Void = {}
    var didDeliver: () -> Void = {}
    @ObservationIgnored let services: RebuildSessionServices
    @ObservationIgnored let setup: RebuildSetupServices
    @ObservationIgnored let verificationStore: RebuildModelVerificationStore
    @ObservationIgnored var job: Task<Void, Never>?
    @ObservationIgnored var sessionID: UUID?
    @ObservationIgnored var configuration: TranscriptionPipelineConfig?
    @ObservationIgnored var capturedTarget: RebuildPasteDestination?
    @ObservationIgnored var startedAt: Date?
    @ObservationIgnored var refreshInFlight = false
    @ObservationIgnored var refreshAgain = false
    @ObservationIgnored let paste: PasteManager
    @ObservationIgnored let delivery: RebuildPasteDelivery
    @ObservationIgnored var retryAudio: RetryAudio?
    @ObservationIgnored var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored var verificationSelection: RebuildModelSelection?
    @ObservationIgnored var verificationAssets: String?
    @ObservationIgnored var previewRequested = false

    struct RetryAudio {
        let url: URL
        let config: TranscriptionPipelineConfig
        let owned: Bool
        let duration: TimeInterval?
    }

    init(
        services: RebuildSessionServices, setup: RebuildSetupServices? = nil,
        verificationDefaults: UserDefaults? = nil, writingInstaller: RebuildWritingInstaller? = nil,
        paste: PasteManager? = nil, delivery: RebuildPasteDelivery? = nil, livePreview: RebuildLivePreview? = nil
    ) {
        self.services = services
        self.livePreview = livePreview ?? RebuildLivePreview()
        self.paste = paste ?? PasteManager()
        self.delivery = delivery ?? RebuildPasteDelivery()
        self.setup = setup ?? .live
        self.writingInstaller = writingInstaller ?? RebuildWritingInstaller()
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

    func handleInterruption(_ event: RecordingInterruption) {
        guard event.sessionID == sessionID else {
            if case .finished(_, let audio?, _) = event { try? FileManager.default.removeItem(at: audio) }
            return
        }
        // A duplicate stop event must not delete audio already in transcription.
        guard phase == .recording, let config = configuration else { return }
        livePreview.stop()
        closeRecorder()
        switch event {
        case .finished(let id, let audio?, let capturedDuration):
            duration = capturedDuration
            notice = "Recording was interrupted. Transcribing the audio captured before it stopped."
            transcribe(url: audio, config: config, id: id, removeAfterward: true)
        case .finished:
            notice = "Recording was interrupted before usable audio was captured. Try again."
            phase = .failed
            sessionID = nil
        case .failed(_, let message):
            notice = message
            phase = .failed
            sessionID = nil
        }
    }

    func toggleRecording() {
        if phase == .recording {
            finishRecording()
            return
        }
        guard phase != .starting, phase != .transcribing else { return }
        beginRecording(practice: false)
    }

    func startPractice() {
        guard !phase.isBusy else { return }
        beginRecording(practice: true)
    }

    func beginRecording(practice: Bool) {
        guard !phase.isBusy, !isInstalling, !maintenanceInProgress else { return }
        let target = practice ? nil : services.capturePasteDestination()
        let mode = AppDefaults.resolveDictationMode(app: target?.bundleIdentifier, allowAppRule: !practice)
        guard mode.selection != setup.selection() || readiness.ready else {
            openSetup()
            return
        }
        prepareSession(practice: practice, target: target, mode: mode, allowContext: !practice)
        if mode.selection != setup.selection(), let id = sessionID {
            phase = .starting
            job = Task { [weak self] in
                guard let self, await checkResolvedMode(mode, id: id) else { return }
                startPreparedRecording()
            }
            return
        }
        startPreparedRecording()
    }

    func startPreparedRecording() {
        if let startAsync = services.startAsync, let id = sessionID {
            phase = .starting
            job = Task { [weak self] in
                guard let self else { return }
                let started = await startAsync(id)
                guard !Task.isCancelled, sessionID == id else { return }
                completeRecordingStart(started)
            }
            return
        }
        guard let id = sessionID else { return }
        completeRecordingStart(services.start(id))
    }

    func completeRecordingStart(_ started: Bool) {
        guard started else {
            notice = services.startError() ?? "The microphone could not start. Check the selected input and try again."
            phase = .failed
            sessionID = nil
            return
        }
        startedAt = Date()
        timing.recording = ProcessInfo.processInfo.systemUptime
        phase = .recording
        if previewRequested, let model = configuration?.parakeetModel {
            livePreview.start(model: model, snapshot: services.previewSnapshot)
        }
        if !isPractice && !AppDefaults.immediateRecording { showRecorder() }
    }

    func finishRecording() {
        guard phase == .recording, let id = sessionID, let config = configuration else { return }
        livePreview.stop()
        timing.stopped = ProcessInfo.processInfo.systemUptime
        duration = startedAt.map { Date().timeIntervalSince($0) }
        guard let url = services.stop() else {
            notice = "No audio was captured. Try a different microphone."
            phase = .failed
            sessionID = nil
            closeRecorder()
            return
        }
        guard services.recordedSignal()?.isSilent != true else {
            rejectSilentRecording(url: url, config: config)
            return
        }
        transcribe(url: url, config: config, id: id, removeAfterward: true)
    }

    /// A dead input yields an all-silent file, and WhisperKit invents text for
    /// silence rather than reporting none. The audio is kept, so Retry can
    /// still force a transcription if the meter was wrong.
    func rejectSilentRecording(url: URL, config: TranscriptionPipelineConfig) {
        retryAudio = RetryAudio(url: url, config: config, owned: true, duration: duration)
        notice = "The microphone recorded only silence. Check the selected microphone, its mute switch and input level."
        phase = .failed
        closeRecorder()
    }

    func importAudio(_ url: URL) {
        guard canImportAudio else {
            notice = fileBlockedReason
            if phase.isBusy || isInstalling || maintenanceInProgress { return }
            openSetup()
            return
        }
        prepareSession(target: services.capturePasteDestination(),
                       mode: AppDefaults.resolveDictationMode(app: nil, allowAppRule: false), allowContext: false)
        guard let id = sessionID, let config = configuration else { return }
        duration = nil
        transcribe(url: url, config: config, id: id, removeAfterward: false)
    }

    func prepareSession(
        practice: Bool = false, target: RebuildPasteDestination?, mode: ResolvedDictationMode, allowContext: Bool
    ) {
        livePreview.stop(clear: true)
        discardRetry()
        duration = nil
        isPractice = practice
        timing = RebuildSessionTiming()
        deliveryStatus = .none
        capturedTarget = target
        effectiveMode = mode
        contextRequested = allowContext && mode.settings.cleanup != .off && mode.settings.writing.contextSource != .none
        writingContext = contextRequested
            ? services.contextCapture.capture(mode.settings.writing.contextSource, target: target) : nil
        sessionID = UUID()
        notice = nil
        var settings = mode.settings
        if practice { settings.cleanup = .off; settings.writing.contextSource = .none }
        configuration = settings.pipeline(sourceApp: target?.bundleIdentifier, context: writingContext)
        previewRequested = AppDefaults.liveTranscriptionPreview && configuration?.provider == .parakeet
        services.configureLivePreview(previewRequested)
    }

}

extension RebuildSession {
    func transcribe(url: URL, config: TranscriptionPipelineConfig, id: UUID, removeAfterward: Bool) {
        if timing.stopped == nil { timing.stopped = ProcessInfo.processInfo.systemUptime }
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
                deliveredTranscript = result.text
                originalTranscript = result.originalText
                timing.recognized = ProcessInfo.processInfo.systemUptime
                // Imports use validated file metadata; live captures keep their measured duration.
                let deliveredDuration = duration ?? result.audioDuration
                let loan = copyTranscript(result.text)
                deliveryStatus = .delivering
                if case .rejected = result.correctionOutcome {
                    notice = "Copied the original transcript. Writing cleanup could not safely preserve your words."
                }
                if case .failed = result.correctionOutcome {
                    notice = "Copied the original transcript. Writing cleanup was unavailable."
                }
                // History must not delay paste or be cancelled by a new recording.
                let persistence = persistInBackground(result, config: config, duration: deliveredDuration)
                if removeAfterward { try? FileManager.default.removeItem(at: url) }
                phase = .completed
                closeRecorder()
                didDeliver()
                if AppDefaults.playCompletionSound { NSSound(named: "Pop")?.play() }
                await pasteTranscript(result.text, sessionID: id, loan: loan)
                if sessionID == id, !Task.isCancelled { services.announce(deliveryStatus.announcement) }
                if let (token, task) = persistence {
                    let message = await task.value
                    if let message, sessionID == id, !Task.isCancelled {
                        notice = [notice, message].compactMap { $0 }.joined(separator: " ")
                    }
                    historyTasks.removeValue(forKey: token)
                    pendingHistoryWrites = historyTasks.count
                }
            } catch {
                guard sessionID == id, !Task.isCancelled else { return }
                retryAudio = RetryAudio(url: url, config: config, owned: removeAfterward, duration: duration)
                retainedForRetry = true
                notice = error.localizedDescription
                phase = .failed
                closeRecorder()
            }
        }
    }

}
