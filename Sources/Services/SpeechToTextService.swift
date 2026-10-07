import Foundation
import os.log
import Observation

internal enum SpeechToTextError: Error, LocalizedError {
    case invalidURL
    case transcriptionFailed(String)
    case localTranscriptionFailed(Error)
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return LocalizedStrings.Errors.invalidAudioFile
        case .transcriptionFailed(let message):
            return LocalizedStrings.Errors.transcriptionFailed
                .substitutingPlaceholder(message)
        case .localTranscriptionFailed(let error):
            return LocalizedStrings.Errors.localTranscriptionFailed
                .substitutingPlaceholder(error.localizedDescription)
        case .noSpeechDetected:
            return LocalizedStrings.Errors.noSpeechDetected
        }
    }
}

/// Routes a transcription request to the correct provider (WhisperKit or
/// Parakeet) based on user settings.
///
/// As of audit item B1, this service ALWAYS returns the provider's raw
/// transcript. Semantic correction now lives exclusively in
/// `TranscriptionPipeline`, which is the sole orchestrator that should call
/// `SemanticCorrectionService`. Tests and rare callers that explicitly want
/// the raw output may still invoke this service directly.
@Observable
internal class SpeechToTextService {
    // Shared singletons by default — one WhisperKit cache per process is the
    // point of `LocalWhisperService.shared`, and the Parakeet daemon is
    // likewise process-wide.
    private let localWhisperService: LocalWhisperTranscribing
    private let parakeetService: ParakeetTranscribing
    private let preparePython: () async throws -> URL

    /// Audit item A5. These were `private let ... = .shared` with no way to
    /// substitute them, so nothing in `transcribeValidated` — provider routing,
    /// the missing-model guard, `ParakeetError.modelNotReady` pass-through,
    /// marker cleaning — was reachable without a downloaded model. The defaults
    /// keep production behaviour byte-identical; the parameters exist so tests
    /// can reach the routing logic.
    init(
        localWhisperService: LocalWhisperTranscribing = LocalWhisperService.shared,
        parakeetService: ParakeetTranscribing = ParakeetService.shared,
        preparePython: @escaping () async throws -> URL = { try await UvBootstrap.ensureVenv() }
    ) {
        self.localWhisperService = localWhisperService
        self.parakeetService = parakeetService
        self.preparePython = preparePython
    }

    /// Runs `AudioValidator` on `url` and surfaces any failure as
    /// `SpeechToTextError.transcriptionFailed(...)`. Returns the URL unchanged
    /// so callers can chain. Centralising the validation here ensures both
    /// `transcribe(audioURL:provider:model:)` and `transcribeRaw(...)` apply the
    /// same checks even if `AudioValidator` evolves.
    @discardableResult
    private func validatedAudioURL(_ url: URL) async throws -> URL {
        let validationResult = await AudioValidator.validateAudioFile(at: url)
        switch validationResult {
        case .valid:
            return url
        case .invalid(let error):
            throw SpeechToTextError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Raw transcription without semantic correction.
    /// Validates the audio file then delegates to the selected provider.
    /// Throws `SpeechToTextError` on validation or transcription failure.
    /// As of audit item B1, `transcribe(_:)` is also raw — this method
    /// remains the explicit/preferred name when callers want to make that
    /// expectation obvious at the call site.
    func transcribeRaw(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel? = nil) async throws -> String {
        let validated = try await validatedAudioURL(audioURL)
        return try await transcribeValidated(audioURL: validated, provider: provider, model: model)
    }

    /// Transcribe an audio file whose validity the caller has ALREADY established.
    ///
    /// Audit item A4: `TranscriptionPipeline` runs `AudioValidator` as its own
    /// step 1 and then called `transcribeRaw`, which validated the same URL a
    /// second time — `AudioValidator` opens and inspects the file, so every
    /// transcription paid for two full passes over it. The pipeline is the
    /// documented sole orchestrator, so it owns validation and calls this;
    /// direct callers keep using `transcribeRaw`, which still validates.
    ///
    /// Only call this when validation has genuinely happened. It is not a
    /// "skip the checks" shortcut.
    func transcribeValidated(
        audioURL: URL,
        provider: TranscriptionProvider,
        model: WhisperModel? = nil,
        pipelineConfig: TranscriptionPipelineConfig? = nil
    ) async throws -> String {
        switch provider {
        case .local:
            guard let model = model else {
                throw SpeechToTextError.transcriptionFailed("Whisper model required for local transcription")
            }
            return try await transcribeWithLocal(audioURL: audioURL, model: model)
        case .parakeet:
            return try await transcribeWithParakeet(audioURL: audioURL, config: pipelineConfig)
        }
    }

    // Audit item B4: `transcribe(audioURL:)` and
    // `transcribe(audioURL:provider:model:)` were removed here.
    //
    // Once audit item B1 moved semantic correction into `TranscriptionPipeline`,
    // `transcribe(audioURL:provider:model:)` became a one-line forward to
    // `transcribeRaw(...)` — two public names for one behaviour, where the
    // shorter one reads as though it still applies correction. That is exactly
    // the misreading the B1 split existed to prevent.
    //
    // Neither had a production caller: the app reaches the providers through
    // `TranscriptionPipeline` → `transcribeValidated(...)`, and direct callers
    // use `transcribeRaw(...)`. The no-argument convenience additionally
    // auto-selected a provider by CPU architecture, duplicating a decision the
    // pipeline config already owns. Both were dead, so they were deleted rather
    // than deprecated.

    /// Delegates to `LocalWhisperService` (WhisperKit / CoreML). Returns the
    /// provider's raw output; semantic correction is applied by
    /// `TranscriptionPipeline` (see audit item B1).
    private func transcribeWithLocal(audioURL: URL, model: WhisperModel) async throws -> String {
        let sessionID = TranscriptionProgress.sessionID
        do {
            let text = try await localWhisperService.transcribe(
                audioFileURL: audioURL,
                model: model,
                progressCallback: { progress in
                    TranscriptionProgress.post(progress, sessionID: sessionID)
                }
            )
            return try Self.cleanedNonEmptyTranscription(text)
        } catch let error as SpeechToTextError {
            // Already a domain error (e.g. .noSpeechDetected) — preserve it
            // instead of burying it under .localTranscriptionFailed.
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SpeechToTextError.localTranscriptionFailed(error)
        }
    }

    /// Delegates to `ParakeetService` (Parakeet-MLX, Apple-Silicon only) and warms up
    /// the MLX correction daemon in parallel when correction is enabled.
    /// Returns the provider's raw output; semantic correction is applied by
    /// `TranscriptionPipeline` (see audit item B1). The warmup remains here so
    /// the MLX daemon can spin up in parallel with the transcription itself.
    private func transcribeWithParakeet(audioURL: URL, config: TranscriptionPipelineConfig?) async throws -> String {
        guard Arch.isAppleSilicon else {
            throw SpeechToTextError.transcriptionFailed("Parakeet requires an Apple Silicon Mac.")
        }
        let options = config
        let semanticCorrectionMode = options?.correctionMode ?? AppDefaults.semanticCorrectionMode
        let parakeetModel = options?.parakeetModel ?? AppDefaults.selectedParakeetModel
        let shouldWarmup = (options?.applySemanticCorrection ?? true) && semanticCorrectionMode != .off
        // Ensure managed Python environment with uv
        let pyURL = try await preparePython()
        let pythonPath = pyURL.path
        do {
            if shouldWarmup {
                // B1: warm up the SAME model correction will actually run.
                // This used to hardcode Llama-3.2-1B when the key was unset while
                // `SemanticCorrectionService` did the same — so both agreed with
                // each other but disagreed with the Dashboard. Now there is one
                // source of truth, which also means the warmup is no longer
                // wasted on a model the correction pass won't use.
                let modelRepo = options?.correctionModelRepo ?? AppDefaults.semanticCorrectionModelRepo
                // Warm up the MLX daemon in parallel, but treat its outcome as
                // non-fatal: a warmup failure must NOT abort an otherwise-good
                // transcription. Its error is swallowed (logged by the daemon).
                async let warmupTask: Void = MLDaemonManager.shared.warmup(type: .mlx, repo: modelRepo)
                let text = try await parakeetService.transcribe(
                    audioFileURL: audioURL, pythonPath: pythonPath, model: parakeetModel
                )
                try? await warmupTask
                return try Self.cleanedNonEmptyTranscription(text)
            } else {
                let text = try await parakeetService.transcribe(
                    audioFileURL: audioURL, pythonPath: pythonPath, model: parakeetModel
                )
                return try Self.cleanedNonEmptyTranscription(text)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Pass through model-not-ready distinctly so UI can redirect to Settings
            if let pe = error as? ParakeetError, pe == .modelNotReady {
                throw pe
            }
            // Preserve domain errors (e.g. .noSpeechDetected) instead of
            // flattening them into a generic transcription failure.
            if let se = error as? SpeechToTextError {
                throw se
            }
            throw SpeechToTextError.transcriptionFailed("Parakeet error: \(error.localizedDescription)")
        }
    }

    // MARK: - Text Cleaning

    /// Cleans transcription text and rejects empty results.
    ///
    /// `cleanTranscriptionText` strips bracketed/parenthesized markers such as
    /// WhisperKit's `[BLANK_AUDIO]` silence marker. A marker-only transcript is
    /// non-empty *before* cleaning (so it passes the provider's `isEmpty`
    /// check) but cleans down to `""`. Returning that empty string silently
    /// pastes nothing; instead we surface a clear no-speech error.
    static func cleanedNonEmptyTranscription(_ text: String) throws -> String {
        let cleaned = cleanTranscriptionText(text)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SpeechToTextError.noSpeechDetected
        }
        return cleaned
    }

    /// Remove only recognized acoustic annotations. Ordinary bracketed content,
    /// code punctuation and line structure belong to the user's transcript.
    private static let acousticMarkers: NSRegularExpression? = {
        let names = [
            "blank audio", "no audio", "silence", "empty", "music", "background music",
            "background noise", "inaudible", "laughter", "laughing", "applause", "coughing",
            "door closing", "door slamming", "phone ringing", "crying", "sighs", "whispers", "shouting"
        ].map { $0.replacingOccurrences(of: " ", with: "[ _]+") }.joined(separator: "|")
        // A quoted literal or an array/function operand is not an acoustic tag.
        let marker = "(?:\\[(?:\(names))\\]|\\((?:\(names))\\))"
        return try? NSRegularExpression(
            pattern: "[ \t]*(?<![\\p{L}\\p{N}_\"'`])" + marker + "(?![\\p{L}\\p{N}_])[ \t]*",
            options: [.caseInsensitive])
    }()

    static func cleanTranscriptionText(_ text: String) -> String {
        guard let markers = acousticMarkers else { return text }
        let cleaned = markers.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: " ")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}
