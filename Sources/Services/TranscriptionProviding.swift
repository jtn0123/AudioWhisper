import Foundation

/// The slice of `LocalWhisperService` that `SpeechToTextService` actually uses.
///
/// Audit item A5. `SpeechToTextService` hardcoded
/// `private let localWhisperService = LocalWhisperService.shared`, so no test
/// could reach it without a real WhisperKit instance — which needs a downloaded
/// multi-hundred-megabyte model. Combined with the equivalent Parakeet
/// hardcoding, that left the routing logic in `transcribeValidated` (provider
/// selection, the missing-model guard, error mapping, marker cleaning)
/// unreachable, and `Services/` stuck around 50% coverage.
///
/// The singletons stay: one WhisperKit cache per process is the point of
/// `LocalWhisperService.shared`. What changes is that the *seam* now exists —
/// `SpeechToTextService.init` defaults to the shared instances, so production
/// behaviour is unchanged, and tests can pass a double.
internal protocol LocalWhisperTranscribing: Sendable {
    func transcribe(
        audioFileURL: URL,
        model: WhisperModel,
        progressCallback: (@Sendable (String) -> Void)?
    ) async throws -> String
}

/// The slice of `ParakeetService` that `SpeechToTextService` actually uses.
/// See `LocalWhisperTranscribing` for why this exists.
internal protocol ParakeetTranscribing: AnyObject {
    func transcribe(audioFileURL: URL, pythonPath: String?) async throws -> String
    func transcribe(audioFileURL: URL, pythonPath: String?, model: ParakeetModel) async throws -> String
}

extension ParakeetTranscribing {
    func transcribe(audioFileURL: URL, pythonPath: String?, model: ParakeetModel) async throws -> String {
        try await transcribe(audioFileURL: audioFileURL, pythonPath: pythonPath)
    }
}

extension LocalWhisperService: LocalWhisperTranscribing {}

extension ParakeetService: ParakeetTranscribing {}
