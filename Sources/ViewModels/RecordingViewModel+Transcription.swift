import AVFoundation
import Foundation

/// The transcription entry points: stop-and-transcribe, transcribe-a-file, and
/// retry.
///
/// Audit item A1. These lived in `ContentView+Recording.swift` — an extension on
/// a SwiftUI `View`, which is re-created on every render and cannot be
/// instantiated in a test without a rendering context. That file measured 0.0%
/// coverage across 440 lines, so the app's primary user flow (record → stop →
/// transcribe → correct → paste) had no automated coverage at all. Meanwhile
/// `RecordingViewModel.startRecording(audioRecorder:permissionManager:)` and
/// `TranscriptionCoordinator.runTranscription(...)` were tested but had **zero**
/// production callers: the ViewModel layer had been built and then never wired
/// up, so the tests that appeared to cover this flow were exercising a copy the
/// app never ran.
///
/// Audit item A3. The three entry points previously carried near-identical
/// ~45-line `Task` bodies that differed only in how the audio URL and duration
/// are obtained and in their cancellation/error tails. Everything between —
/// `checkCancellation`, the pipeline call, the `TranscriptionRunContext` — was
/// duplicated verbatim. That shared body is now `runTranscriptionFlow`.
///
/// View-owned values (`hasShownFirstModelUseHint`, dashboard presentation) are
/// passed in rather than read here, so the view's `@AppDefault` wrapper stays
/// the writer for the hint flag and `WindowCoordinator` keeps logging the
/// redirect reason — both behaviours are preserved exactly.
internal extension RecordingViewModel {

    // MARK: - Entry Points

    /// Stops the recorder and transcribes what it captured.
    /// Generic over `AudioRecording` so tests can drive it: `AudioEngineRecorder`
    /// is `final` and cannot be subclassed (audit item D1).
    func stopAndProcess<Recorder: AudioRecording>(
        audioRecorder: Recorder,
        hasShownFirstModelUseHint: Bool,
        setHintShown: @escaping () -> Void,
        presentDashboard: @escaping (String) -> Void
    ) {
        cancelProcessing()
        NotificationCenter.default.post(name: .recordingStopped, object: nil)

        let shouldHint = shouldHintThisRun(alreadyShown: hasShownFirstModelUseHint)
        if shouldHint { showFirstModelUseHint = true }

        runTranscriptionFlow(FlowSpec(
            progressMessage: "Preparing audio...",
            initialSource: .liveRecording(sessionDuration: 0),
            shouldHintThisRun: shouldHint,
            setHintShown: setHintShown,
            resolveAudio: { [weak self] in
                guard let audioURL = audioRecorder.stopRecording() else {
                    throw NSError(
                        domain: "AudioRecorder",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.failedToGetRecordingURL]
                    )
                }
                let source = TranscriptionSource.liveRecording(
                    sessionDuration: audioRecorder.lastRecordingDuration
                )

                guard !audioURL.path.isEmpty else {
                    // Reported with the resolved source so the error tail's
                    // dashboard reason matches the live-recording flow.
                    throw ResolvedAudioFailure(
                        source: source,
                        underlying: NSError(
                            domain: "AudioRecorder",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: LocalizedStrings.Errors.recordingURLEmpty]
                        )
                    )
                }

                self?.lastAudioURL = audioURL
                return (audioURL, source)
            },
            onCancelled: { [weak self] in
                self?.cancelTail(shouldHintThisRun: shouldHint, setHintShown: setHintShown)
            },
            onFailure: { [weak self] error, source in
                self?.handleTranscriptionError(
                    error,
                    source: source,
                    transcriptionProvider: AppDefaults.transcriptionProvider,
                    shouldHintThisRun: shouldHint,
                    setHintShown: setHintShown,
                    presentDashboard: presentDashboard
                )
            }
        ))
    }

    /// Transcribes an audio file the user imported.
    func transcribeExternalAudioFile(
        _ audioURL: URL,
        hasShownFirstModelUseHint: Bool,
        setHintShown: @escaping () -> Void,
        presentDashboard: @escaping (String) -> Void
    ) {
        cancelProcessing()
        capturedRecordingSettings = nil
        capturePasteTarget()

        let shouldHint = shouldHintThisRun(alreadyShown: hasShownFirstModelUseHint)
        if shouldHint { showFirstModelUseHint = true }

        runTranscriptionFlow(FlowSpec(
            progressMessage: "Transcribing file...",
            initialSource: .importedFile(audioURL, estimatedDuration: 0),
            shouldHintThisRun: shouldHint,
            setHintShown: setHintShown,
            resolveAudio: { [weak self] in
                // Set before the duration load, matching the prior ordering:
                // `showLastAudioFile` / `retryLastTranscription` can be invoked
                // by the user while the asset is still loading.
                self?.lastAudioURL = audioURL

                // Real file duration from AVAsset — more accurate than file size.
                let asset = AVAsset(url: audioURL)
                let estimatedDuration = (try? await asset.load(.duration).seconds) ?? 0
                return (audioURL, .importedFile(audioURL, estimatedDuration: estimatedDuration))
            },
            onCancelled: { [weak self] in
                self?.cancelTail(shouldHintThisRun: shouldHint, setHintShown: setHintShown)
            },
            onFailure: { [weak self] error, source in
                self?.handleTranscriptionError(
                    error,
                    source: source,
                    transcriptionProvider: AppDefaults.transcriptionProvider,
                    shouldHintThisRun: shouldHint,
                    setHintShown: setHintShown,
                    presentDashboard: presentDashboard
                )
            }
        ))
    }

    /// Re-runs the last transcription against the audio file already on disk.
    ///
    /// Unlike the other two entry points this never advances the first-model-use
    /// hint (the hint has necessarily been shown already) and its failure tail
    /// surfaces the error directly rather than redirecting to the dashboard —
    /// both preserved from the original implementation.
    func retryLastTranscription() {
        guard !isProcessing else { return }

        guard let audioURL = lastAudioURL else {
            presentError(LocalizedStrings.Errors.noAudioFileToRetry)
            return
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            presentError(LocalizedStrings.Errors.audioFileMissingRetry)
            lastAudioURL = nil
            return
        }

        cancelProcessing()

        runTranscriptionFlow(FlowSpec(
            progressMessage: "Retrying transcription...",
            // Retry replays an existing live recording, so `.liveRecording` with
            // a nil duration — matching the prior behaviour of passing
            // `duration: nil` to history.
            initialSource: .liveRecording(sessionDuration: nil),
            shouldHintThisRun: false,
            setHintShown: {},
            resolveAudio: { (audioURL, .liveRecording(sessionDuration: nil)) },
            onCancelled: { [weak self] in
                self?.isProcessingForFlow = false
                self?.transcriptionStartTime = nil
                self?.awaitingSemanticPaste = false
            },
            onFailure: { [weak self] error, _ in
                guard let self else { return }
                self.presentError(error.localizedDescription)
                self.isProcessingForFlow = false
                self.transcriptionStartTime = nil
            }
        ))
    }

    // MARK: - Shared Flow

    /// Thrown by a `resolveAudio` closure that has already determined the
    /// `TranscriptionSource` and wants the failure attributed to it, so the
    /// error tail picks the right dashboard reason.
    private struct ResolvedAudioFailure: Error {
        let source: TranscriptionSource
        let underlying: Error
    }

    /// Everything that varies between the three transcription entry points.
    ///
    /// Grouped into a type rather than passed as seven parameters: the shared
    /// runner genuinely needs all of them, and a struct names each at the call
    /// site instead of relying on argument order.
    private struct FlowSpec {
        /// Progress text shown while the run starts.
        let progressMessage: String
        /// Source assumed until `resolveAudio` reports the definitive one; used
        /// to attribute a failure that happens before resolution.
        let initialSource: TranscriptionSource
        let shouldHintThisRun: Bool
        let setHintShown: () -> Void
        /// Produces the audio URL and the definitive `TranscriptionSource`.
        let resolveAudio: () async throws -> (URL, TranscriptionSource)
        let onCancelled: () -> Void
        let onFailure: (Error, TranscriptionSource) async -> Void
    }

    /// The body shared by all three entry points (audit item A3).
    ///
    /// `resolveAudio` supplies the audio URL and the definitive
    /// `TranscriptionSource`; everything after it is identical across the three
    /// callers. `onCancelled` and `onFailure` are injected because retry's tails
    /// genuinely differ from the other two.
    private func runTranscriptionFlow(_ spec: FlowSpec) {
        // Set before creating the Task so a hotkey press arriving in the same
        // tick sees the in-flight state (the original comment: "prevent race
        // condition").
        sessionID = UUID()
        let id = sessionID
        let config = capturedRecordingSettings ?? makePipelineConfig()
        capturedRecordingSettings = nil
        showError = false
        showSuccess = false
        correctionFailedMessage = nil
        completedAudioDuration = nil
        isProcessingForFlow = true
        transcriptionStartTime = Date()
        cancellationTail = spec.onCancelled

        processingTask = Task { [weak self] in
            guard let self, self.isCurrentSession(id) else { return }
            self.progressMessage = spec.progressMessage

            // Held outside the `do` so the failure tail reports the most
            // specific source known at the point of failure.
            var source = spec.initialSource

            do {
                try Task.checkCancellation()

                let resolved: (URL, TranscriptionSource)
                do {
                    resolved = try await spec.resolveAudio()
                } catch let failure as ResolvedAudioFailure {
                    source = failure.source
                    throw failure.underlying
                }
                source = resolved.1

                try Task.checkCancellation()
                guard self.isCurrentSession(id) else { return }
                self.completedAudioDuration = source.duration

                let result = try await TranscriptionProgress.$sessionID.withValue(id) {
                    try await self.coordinator.runTranscription(audioURL: resolved.0, config: config)
                }

                try Task.checkCancellation()

                guard self.isCurrentSession(id) else { return }
                await self.finishTranscription(
                    text: result.text,
                    correctionOutcome: result.correctionOutcome,
                    context: TranscriptionRunContext(
                        source: source,
                        transcriptionProvider: config.provider,
                        selectedWhisperModel: config.whisperModel ?? AppDefaults.selectedWhisperModel,
                        shouldHintThisRun: spec.shouldHintThisRun,
                        setHintShown: spec.setHintShown,
                        sessionID: id
                    )
                )
            } catch is CancellationError {
                guard self.isCurrentSession(id) else { return }
                spec.onCancelled()
            } catch {
                guard self.isCurrentSession(id), !Task.isCancelled else { return }
                await spec.onFailure(error, source)
            }
            if self.isCurrentSession(id) { self.cancellationTail = nil }
        }
    }

    /// Builds the pipeline config from current settings and runs it through the
    /// coordinator.
    ///
    /// Audit item A1: this replaces `ContentView+Recording.runTranscriptionPipeline`,
    /// which constructed its own `TranscriptionPipeline` inline and so bypassed
    /// `TranscriptionCoordinator.runTranscription` entirely — leaving that method
    /// with no production callers despite having tests.
    func makePipelineConfig() -> TranscriptionPipelineConfig {
        let provider = AppDefaults.transcriptionProvider
        return TranscriptionPipelineConfig(
            provider: provider,
            whisperModel: provider == .local ? AppDefaults.selectedWhisperModel : nil,
            applySemanticCorrection: AppDefaults.semanticCorrectionMode != .off,
            sourceAppBundleId: currentSourceAppInfo().bundleIdentifier
        )
    }

    // MARK: - Helpers

    private func shouldHintThisRun(alreadyShown: Bool) -> Bool {
        !alreadyShown && isLocalModelInvocationPlanned(
            transcriptionProvider: AppDefaults.transcriptionProvider
        )
    }

    /// Cancellation tail shared by `stopAndProcess` and
    /// `transcribeExternalAudioFile`: clear the in-flight state and retire the
    /// hint, since a cancelled run still counts as having offered it.
    private func cancelTail(shouldHintThisRun: Bool, setHintShown: @escaping () -> Void) {
        isProcessingForFlow = false
        transcriptionStartTime = nil
        if shouldHintThisRun {
            setHintShown()
            showFirstModelUseHint = false
        }
    }

    private func presentError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
