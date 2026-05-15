import SwiftUI
import AppKit
import AVFoundation
import os.log

/// Identifies the origin of a transcription so the post-transcription tail
/// (history save, paste, success UI, dashboard redirect on missing models) can
/// branch on the right metadata. Introduced by audit item C1 to consolidate
/// the duplicated "finish transcription" path in `ContentView+Recording`.
internal enum TranscriptionSource {
    /// Live recording captured by `AudioEngineRecorder`. The associated
    /// `sessionDuration` comes from the recorder and may be `nil` if the
    /// engine couldn't compute one (matches the prior pass-through behaviour).
    case liveRecording(sessionDuration: TimeInterval?)
    /// User-imported audio file. The associated `audioURL` is the source file
    /// and `estimatedDuration` is read from the file's `AVAsset` duration.
    case importedFile(URL, estimatedDuration: TimeInterval)

    /// Duration used for analytics and the history record. Optional so the
    /// live-recording path can flow a `nil` duration through unchanged when
    /// the recorder couldn't compute one.
    var duration: TimeInterval? {
        switch self {
        case .liveRecording(let sessionDuration): return sessionDuration
        case .importedFile(_, let estimatedDuration): return estimatedDuration
        }
    }

    /// Dashboard redirect reason tag for "model not downloaded" errors.
    /// Live and file flows surface distinct reasons so analytics/logs can tell
    /// them apart.
    func dashboardReason(for provider: TranscriptionProvider) -> String {
        switch (self, provider) {
        case (.liveRecording, .local): return "liveLocalModelMissing"
        case (.liveRecording, .parakeet): return "liveParakeetModelMissing"
        case (.importedFile, .local): return "fileLocalModelMissing"
        case (.importedFile, .parakeet): return "fileParakeetModelMissing"
        }
    }
}

/// ViewModel that manages recording state and the transcription pipeline.
/// Consolidates state from ContentView to reduce complexity and improve testability.
@MainActor
@Observable
final class RecordingViewModel {
    // MARK: - Core Recording State

    private(set) var isProcessing = false
    var progressMessage = "Processing..."
    var transcriptionStartTime: Date?

    // MARK: - UI State

    var showError = false
    var errorMessage = ""
    var showSuccess = false
    var isHandlingSpaceKey = false
    var showFirstModelUseHint = false
    /// Non-nil when a semantic-correction pass failed and the UI should show a
    /// brief warning banner. The raw transcript is still copied/pasted; this
    /// flag exists so the user knows correction didn't apply. See audit item
    /// A4. Cleared automatically after a short delay to match the existing
    /// success-toast pattern.
    var correctionFailedMessage: String?

    // MARK: - Paste State

    var targetAppForPaste: NSRunningApplication?
    var lastAudioURL: URL?
    var awaitingSemanticPaste = false
    var lastSourceAppInfo: SourceAppInfo?

    // MARK: - Dependencies

    let speechService: SpeechToTextService
    let pasteManager: PasteManager
    let semanticCorrectionService: SemanticCorrectionService
    let soundManager: SoundManager
    let statusViewModel: StatusViewModel
    /// Coordinator that owns the transcription pipeline and the
    /// post-transcription tail (history save, metrics, correction-failure
    /// surfacing, error mapping). Introduced by audit item A2 to split
    /// orchestration concerns out of the view model. Not `private` so tests
    /// can inject a substitute (e.g. backed by mock services).
    let coordinator: TranscriptionCoordinator

    // MARK: - Internal State

    private var processingTask: Task<Void, Never>?
    /// Not `private` because `setupNotificationObservers` / `stopNotificationObservers`
    /// live in the `RecordingViewModel+Paste.swift` extension.
    var notificationTasks: [Task<Void, Never>] = []

    // MARK: - Initialization

    /// Creates a new RecordingViewModel with the specified dependencies.
    /// All parameters have default values that can be overridden for testing.
    init(
        speechService: SpeechToTextService,
        pasteManager: PasteManager,
        semanticCorrectionService: SemanticCorrectionService,
        soundManager: SoundManager,
        statusViewModel: StatusViewModel,
        coordinator: TranscriptionCoordinator? = nil
    ) {
        self.speechService = speechService
        self.pasteManager = pasteManager
        self.semanticCorrectionService = semanticCorrectionService
        self.soundManager = soundManager
        self.statusViewModel = statusViewModel
        self.coordinator = coordinator ?? TranscriptionCoordinator(
            speechService: speechService,
            correctionService: semanticCorrectionService
        )
        // The coordinator writes back to the VM (errorMessage, isProcessing,
        // etc.) via a weak reference; wire it up here so callers don't have
        // to remember to.
        self.coordinator.viewModel = self
    }

    /// Convenience initializer with default dependencies.
    convenience init() {
        self.init(
            speechService: SpeechToTextService(),
            pasteManager: PasteManager(),
            semanticCorrectionService: SemanticCorrectionService(),
            soundManager: SoundManager(),
            statusViewModel: StatusViewModel()
        )
    }

    /// Allows the coordinator (and other internal helpers) to clear the
    /// `isProcessing` flag without exposing a public setter — the property
    /// remains `private(set)` for the view layer.
    func markProcessingFinished() {
        isProcessing = false
    }

    // MARK: - Lifecycle

    func onAppear(permissionManager: PermissionManager, loadProvider: () -> Void) {
        setupNotificationObservers()
        permissionManager.checkPermissionState()
        loadProvider()
    }

    func onDisappear() {
        stopNotificationObservers()
        cancelProcessing()
        lastAudioURL = nil
    }

    // MARK: - Recording Actions

    func startRecording(audioRecorder: AudioEngineRecorder, permissionManager: PermissionManager) {
        if permissionManager.microphonePermissionState != .granted {
            permissionManager.requestPermissionWithEducation()
            return
        }

        lastAudioURL = nil

        let success = audioRecorder.startRecording()
        if !success {
            errorMessage = LocalizedStrings.Errors.failedToStartRecording
            showError = true
        }
    }

    func stopAndProcess(
        audioRecorder: AudioEngineRecorder,
        transcriptionProvider: TranscriptionProvider,
        selectedWhisperModel: WhisperModel,
        hasShownFirstModelUseHint: Bool,
        setHintShown: @escaping () -> Void
    ) {
        processingTask?.cancel()
        NotificationCenter.default.post(name: .recordingStopped, object: nil)

        let shouldHintThisRun = !hasShownFirstModelUseHint && isLocalModelInvocationPlanned(
            transcriptionProvider: transcriptionProvider
        )
        if shouldHintThisRun { showFirstModelUseHint = true }

        isProcessing = true
        transcriptionStartTime = Date()

        processingTask = Task {
            progressMessage = "Preparing audio..."

            // Capture a stable `liveRecording` source value once we know the
            // session duration; reused for both the success and error tails
            // so dashboard reasons line up.
            var source: TranscriptionSource = .liveRecording(sessionDuration: 0)

            do {
                try Task.checkCancellation()
                guard let audioURL = audioRecorder.stopRecording() else {
                    throw NSError(
                        domain: "AudioRecorder",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.failedToGetRecordingURL]
                    )
                }
                let sessionDuration = audioRecorder.lastRecordingDuration
                source = .liveRecording(sessionDuration: sessionDuration)

                guard !audioURL.path.isEmpty else {
                    throw NSError(
                        domain: "AudioRecorder",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.recordingURLEmpty]
                    )
                }

                lastAudioURL = audioURL
                try Task.checkCancellation()

                let mode = AppDefaults.semanticCorrectionMode
                let sourceBundleId: String? = currentSourceAppInfo().bundleIdentifier

                if mode != .off {
                    progressMessage = "Semantic correction..."
                }

                // After audit item B1, correction is owned by TranscriptionPipeline.
                // After audit item A2, the pipeline is owned by the
                // coordinator so the view model only sees the result.
                let pipelineConfig = TranscriptionPipelineConfig(
                    provider: transcriptionProvider,
                    whisperModel: transcriptionProvider == .local ? selectedWhisperModel : nil,
                    applySemanticCorrection: mode != .off,
                    sourceAppBundleId: sourceBundleId
                )
                let result = try await coordinator.runTranscription(
                    audioURL: audioURL,
                    config: pipelineConfig
                )

                try Task.checkCancellation()

                await finishTranscription(
                    text: result.text,
                    correctionOutcome: result.correctionOutcome,
                    context: TranscriptionRunContext(
                        source: source,
                        transcriptionProvider: transcriptionProvider,
                        selectedWhisperModel: selectedWhisperModel,
                        shouldHintThisRun: shouldHintThisRun,
                        setHintShown: setHintShown
                    )
                )

            } catch is CancellationError {
                isProcessing = false
                transcriptionStartTime = nil
                if shouldHintThisRun {
                    setHintShown()
                    showFirstModelUseHint = false
                }
            } catch {
                handleTranscriptionError(
                    error,
                    source: source,
                    transcriptionProvider: transcriptionProvider,
                    shouldHintThisRun: shouldHintThisRun,
                    setHintShown: setHintShown
                )
            }
        }
    }

    func cancelProcessing() {
        processingTask?.cancel()
        processingTask = nil
    }

    // MARK: - Private Helpers

    private func isLocalModelInvocationPlanned(transcriptionProvider: TranscriptionProvider) -> Bool {
        if transcriptionProvider == .local || transcriptionProvider == .parakeet {
            return true
        }
        return AppDefaults.semanticCorrectionMode == .localMLX
    }

    // MARK: - Coordinator Forwarders (audit item A2)
    //
    // These forwarders preserve the public surface that `ContentView+Recording`
    // and tests already use, while delegating the actual logic to
    // `TranscriptionCoordinator`. They are thin and intentionally unchanged
    // in signature.

    /// Forwards to `TranscriptionCoordinator.finishTranscription(...)`. See
    /// the coordinator for behaviour.
    func finishTranscription(
        text: String,
        correctionOutcome: CorrectionOutcome? = nil,
        context: TranscriptionRunContext
    ) async {
        await coordinator.finishTranscription(
            text: text,
            correctionOutcome: correctionOutcome,
            context: context
        )
    }

    /// Forwards to `TranscriptionCoordinator.handleTranscriptionError(...)`.
    /// See the coordinator for behaviour.
    func handleTranscriptionError(
        _ error: Error,
        source: TranscriptionSource,
        transcriptionProvider: TranscriptionProvider,
        shouldHintThisRun: Bool,
        setHintShown: @escaping () -> Void,
        presentDashboard: ((String) -> Void)? = nil
    ) {
        coordinator.handleTranscriptionError(
            error,
            source: source,
            transcriptionProvider: transcriptionProvider,
            shouldHintThisRun: shouldHintThisRun,
            setHintShown: setHintShown,
            presentDashboard: presentDashboard
        )
    }

    /// Drives the success UI (chime, paste scheduling, fade-out). Called by
    /// `TranscriptionCoordinator.finishTranscription(...)` after the history
    /// save + metrics tail. Internal so the coordinator can invoke it.
    func showConfirmationAndPaste(text: String) {
        Logger.paste.debug("showConfirmationAndPaste called with text length: \(text.count)")
        showSuccess = true
        isProcessing = false
        soundManager.playCompletionSound()

        let enableSmartPaste = AppDefaults.enableSmartPaste
        Logger.paste.debug("showConfirmationAndPaste: enableSmartPaste = \(enableSmartPaste)")

        if enableSmartPaste {
            let shouldPasteNow = !awaitingSemanticPaste
            if shouldPasteNow {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.performUserTriggeredPaste()
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard let self = self else { return }
                let recordWindow = NSApp.windows.first { $0.title == WindowTitles.recording }

                let onFadeComplete = {
                    NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
                    self.showSuccess = false
                }

                if let window = recordWindow {
                    self.fadeOutWindow(window, completion: onFadeComplete)
                } else if let keyWindow = NSApplication.shared.keyWindow {
                    self.fadeOutWindow(keyWindow, completion: onFadeComplete)
                } else {
                    onFadeComplete()
                }
            }
        }
    }

}
