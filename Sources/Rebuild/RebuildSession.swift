import AppKit
import Observation

/// The rebuild has one owner for a recording or file job. Views never record,
/// request permissions, transcribe, or paste independently.
@MainActor
@Observable
final class RebuildSession {
    let writingInstaller: RebuildWritingInstaller
    let livePreview: RebuildLivePreview
    private(set) var phase: RebuildPhase = .idle
    var readiness = RebuildReadiness()
    var transcript = ""
    private(set) var deliveredTranscript = ""
    private(set) var isPractice = false
    private(set) var timing = RebuildSessionTiming()
    private(set) var pendingHistoryWrites = 0
    @ObservationIgnored private var historyTasks: [UUID: Task<String?, Never>] = [:]
    private(set) var originalTranscript: String?
    var notice: String?
    var setupError: String?
    private(set) var isInstalling = false
    var maintenanceInProgress = false
    var modelDeletionRequested = false
    var modelRemovalError: String?
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
    @ObservationIgnored private var capturedTarget: RebuildPasteDestination?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var refreshInFlight = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private let paste: PasteManager
    @ObservationIgnored private let delivery: RebuildPasteDelivery
    @ObservationIgnored private var retryAudio: RetryAudio?
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var verificationSelection: RebuildModelSelection?
    @ObservationIgnored private var verificationAssets: String?
    @ObservationIgnored private var previewRequested = false

    private struct RetryAudio {
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

    private func handleInterruption(_ event: RecordingInterruption) {
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
        guard phase != .starting, phase != .transcribing else { return }
        beginRecording(practice: false)
    }

    func startPractice() {
        guard !phase.isBusy else { return }
        beginRecording(practice: true)
    }

    private func beginRecording(practice: Bool) {
        guard readiness.ready, !isInstalling, !maintenanceInProgress else {
            openSetup()
            return
        }
        prepareSession(practice: practice)
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

    private func completeRecordingStart(_ started: Bool) {
        guard started else {
            phase = .failed
            notice = services.startError() ?? "The microphone could not start. Check the selected input and try again."
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
            phase = .failed
            notice = "No audio was captured. Try a different microphone."
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
    private func rejectSilentRecording(url: URL, config: TranscriptionPipelineConfig) {
        retryAudio = RetryAudio(url: url, config: config, owned: true, duration: duration)
        phase = .failed
        notice = "The microphone recorded only silence. Check the selected microphone, its mute switch and input level."
        closeRecorder()
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

    private func prepareSession(practice: Bool = false) {
        livePreview.stop(clear: true)
        discardRetry()
        duration = nil
        isPractice = practice
        timing = RebuildSessionTiming()
        capturedTarget = practice ? nil : services.capturePasteDestination()
        sessionID = UUID()
        notice = nil
        configuration = TranscriptionPipelineConfig(
            provider: AppDefaults.transcriptionProvider, whisperModel: AppDefaults.selectedWhisperModel,
            applySemanticCorrection: !practice && AppDefaults.semanticCorrectionMode != .off,
            sourceAppBundleId: capturedTarget?.bundleIdentifier, parakeetModel: AppDefaults.selectedParakeetModel,
            correctionMode: AppDefaults.semanticCorrectionMode,
            correctionModelRepo: AppDefaults.semanticCorrectionModelRepo,
            formatting: .current
        )
        previewRequested = AppDefaults.liveTranscriptionPreview && configuration?.provider == .parakeet
        services.configureLivePreview(previewRequested)
    }

}

extension RebuildSession {
    private func transcribe(url: URL, config: TranscriptionPipelineConfig, id: UUID, removeAfterward: Bool) {
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
                // Live captures keep their measured elapsed time. Imports and
                // imported retries use the file metadata already validated by
                // the pipeline, without opening the audio a second time.
                let deliveredDuration = duration ?? result.audioDuration
                let loan = copyTranscript(result.text)
                if case .rejected = result.correctionOutcome {
                    notice = "Copied the original transcript. Writing cleanup could not safely preserve your words."
                }
                if case .failed = result.correctionOutcome {
                    notice = "Copied the original transcript. Writing cleanup was unavailable."
                }
                // History is independent after a valid result is copied. A slow
                // write must not delay paste, and a new recording must not cancel it.
                let persistence = persistInBackground(result, config: config, duration: deliveredDuration)
                if removeAfterward { try? FileManager.default.removeItem(at: url) }
                phase = .completed
                closeRecorder()
                didDeliver()
                if AppDefaults.playCompletionSound { NSSound(named: "Pop")?.play() }
                await pasteTranscript(result.text, sessionID: id, loan: loan)
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
                phase = .failed
                notice = error.localizedDescription
                closeRecorder()
            }
        }
    }

}

extension RebuildSession {
    private func persistInBackground(
        _ result: TranscriptionResult, config: TranscriptionPipelineConfig, duration: TimeInterval?
    ) -> (UUID, Task<String?, Never>)? {
        guard !isPractice else { return nil }
        let token = UUID()
        let task = Task { @MainActor [services] () -> String? in
            do {
                if let save = services.saveResult {
                    try await save(result, config, duration)
                } else {
                    try await services.save(result.text, config, duration)
                }
                return nil
            } catch {
                return "Copied your transcript, but history could not be saved: \(error.localizedDescription)"
            }
        }
        historyTasks[token] = task
        pendingHistoryWrites = historyTasks.count
        return (token, task)
    }

    func waitForHistoryWrites() async {
        while !historyTasks.isEmpty {
            for task in Array(historyTasks.values) { _ = await task.value }
            await Task.yield()
        }
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
        timing = RebuildSessionTiming()
        notice = nil
        duration = audio.duration
        guard let id = sessionID else { return }
        transcribe(url: audio.url, config: audio.config, id: id, removeAfterward: audio.owned)
    }

    private func discardRetry() {
        if let audio = retryAudio, audio.owned { try? FileManager.default.removeItem(at: audio.url) }
        retryAudio = nil
    }

    /// What Smart Paste borrowed from the clipboard, to give back afterwards.
    struct ClipboardLoan {
        let id = UUID()
        let keeper: ClipboardKeeper
        let saved: ClipboardKeeper.Snapshot
    }

    /// Lends the clipboard only when the user wants it back and a paste is
    /// going to happen; otherwise the transcript simply stays on it.
    private func copyTranscript(_ text: String) -> ClipboardLoan? {
        guard AppDefaults.enableSmartPaste, capturedTarget != nil, let keeper = services.clipboardKeeper() else {
            services.copy(text)
            return nil
        }
        let loan = ClipboardLoan(keeper: keeper, saved: keeper.save())
        keeper.copy(text, loan: loan.id)
        return loan
    }

    private func pasteTranscript(_ text: String, sessionID id: UUID, loan: ClipboardLoan?) async {
        guard AppDefaults.enableSmartPaste, let target = capturedTarget else {
            timing.delivered = ProcessInfo.processInfo.systemUptime
            timing.delivery = "Copied to clipboard"
            return
        }
        let copy: (String) -> Void = loan.map { loan in { loan.keeper.copy($0, loan: loan.id) } } ?? services.copy
        let outcome = await delivery.deliver(text, to: target, paste: paste, copy: copy) { [weak self] in
            self?.sessionID == id
        }
        if sessionID == id, !Task.isCancelled {
            timing.delivered = ProcessInfo.processInfo.systemUptime
            switch outcome {
            case .confirmed: timing.delivery = "Paste confirmed"
            case .unverified: timing.delivery = "Paste sent; confirmation unavailable"
            case .failed, .cancelled: timing.delivery = "Copied; paste manually"
            }
        }
        if let loan { await giveBack(loan, after: outcome) }
        guard !Task.isCancelled, sessionID == id else { return }
        if outcome == .failed { notice = "Copied. Paste manually with Command V." }
    }

    /// A failed or abandoned paste keeps the transcript for pasting by hand.
    /// One that could not be seen landing gets a moment to be read first.
    private func giveBack(_ loan: ClipboardLoan, after outcome: RebuildPasteDelivery.Outcome) async {
        switch outcome {
        case .confirmed: break
        case .unverified:
            do { try await Task.sleep(for: delivery.restoreGrace) } catch { return }
        case .failed, .cancelled: return
        }
        loan.keeper.restore(loan.saved, loan: loan.id)
    }

    func removeVoiceModel() async {
        guard !phase.isBusy, !isInstalling, !maintenanceInProgress else { return }
        maintenanceInProgress = true
        modelRemovalError = nil
        defer { maintenanceInProgress = false }
        do {
            try await setup.remove(setup.selection())
            await refreshSetup()
        } catch { modelRemovalError = error.localizedDescription }
    }

    var captureIdentity: UUID? { sessionID }
    var recordingDestinationName: String {
        AppDefaults.enableSmartPaste ? (capturedTarget?.displayName ?? "Clipboard") : "Clipboard"
    }

    func cancel() {
        livePreview.stop(clear: true)
        discardRetry()
        sessionID = nil
        job?.cancel()
        job = nil
        services.cancel()
        phase = .idle
        notice = nil
        closeRecorder()
    }
    var recordingActionTitle: String {
        if phase == .starting { return "Connecting microphone…" }
        if phase == .recording { return "Finish recording" }
        if phase == .transcribing { return "Transcribing…" }
        if isInstalling { return "Installing…" }
        if isVerifyingVoiceModel { return "Verifying…" }
        if maintenanceInProgress { return "Updating voice model…" }
        return readiness.ready ? "Start recording" : "Finish setup"
    }

    var canToggleRecording: Bool {
        phase == .recording || (!phase.isBusy && !isInstalling && !maintenanceInProgress)
    }

    var recordingBlockedReason: String? {
        if phase == .recording { return nil }
        if let reason = fileBlockedReason { return reason }
        return readiness.microphoneGranted ? nil : "Allow microphone access in Voice Models."
    }

    var canImportAudio: Bool { fileBlockedReason == nil }

    var fileBlockedReason: String? {
        if phase == .starting { return "Wait for the microphone to connect or cancel." }
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

extension RebuildSession {
    /// When the active recording began, for elapsed-time display. `phase` is
    /// observed, so views re-read this whenever recording starts or stops.
    var recordingStartedAt: Date? { phase == .recording ? startedAt : nil }

    var canUseOriginal: Bool {
        !phase.isBusy && originalTranscript != nil && originalTranscript != transcript
    }

    func useOriginalTranscript() {
        guard canUseOriginal, let originalTranscript else { return }
        transcript = originalTranscript
        services.copy(originalTranscript)
        notice = "Original copied. Paste manually with Command V."
    }
}
