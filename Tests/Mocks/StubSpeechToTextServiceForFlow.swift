import Foundation
@testable import AudioWhisper

/// Stub provider for driving `RecordingViewModel`'s transcription flow end to
/// end without WhisperKit or Parakeet.
///
/// `SpeechToTextService` is a non-final class and `RecordingViewModel` injects
/// it, so overriding the transcription entry point is a legitimate seam.
///
/// The override is on `transcribeValidated(...)`, not `transcribeRaw(...)`:
/// after audit item A4 the pipeline validates the audio itself as step 1 and
/// calls the validated entry point, so overriding only `transcribeRaw` would
/// fall through to the real provider. `transcribeRaw` is overridden too and
/// delegates here, exactly as production does.
@MainActor
final class StubSpeechToTextServiceForFlow: SpeechToTextService, @unchecked Sendable {
    /// What the provider returns. Defaults to a fixed transcript.
    var result: Result<String, Error> = .success("stub transcript")

    /// Suspends before returning, so a test can cancel a run that is genuinely
    /// mid-flight rather than racing an already-finished Task.
    var delay: Duration?
    var handler: ((URL) async throws -> String)?

    private(set) var callCount = 0
    private(set) var lastAudioURL: URL?
    private(set) var lastProvider: TranscriptionProvider?

    override func transcribeValidated(
        audioURL: URL,
        provider: TranscriptionProvider,
        model: WhisperModel? = nil
    ) async throws -> String {
        callCount += 1
        lastAudioURL = audioURL
        lastProvider = provider
        if let handler { return try await handler(audioURL) }
        if let delay {
            try await Task.sleep(for: delay)
        }
        return try result.get()
    }

    override func transcribeRaw(
        audioURL: URL,
        provider: TranscriptionProvider,
        model: WhisperModel? = nil
    ) async throws -> String {
        try await transcribeValidated(audioURL: audioURL, provider: provider, model: model)
    }
}
