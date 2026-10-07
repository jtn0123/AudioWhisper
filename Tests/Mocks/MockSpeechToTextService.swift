import Foundation
@testable import AudioWhisper

/// Mock implementation for testing transcription flows. It mirrors the
/// `transcribeRaw` surface `SpeechToTextService` vends, kept in step by hand.
@MainActor
final class MockSpeechToTextService {
    var transcriptionResult: Result<String, Error> = .success("Mock transcription")
    var transcribeRawResult: Result<String, Error>?
    var lastAudioURL: URL?
    var lastProvider: TranscriptionProvider?
    var lastModel: WhisperModel?
    var callCount = 0
    var transcribeRawCallCount = 0

    /// Delay to simulate async operation
    var simulatedDelay: TimeInterval = 0

    func transcribeRaw(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel?) async throws -> String {
        transcribeRawCallCount += 1
        lastAudioURL = audioURL
        lastProvider = provider
        lastModel = model

        if simulatedDelay > 0 {
            try? await Task.sleep(for: .milliseconds(Int(simulatedDelay * 1000)))
        }

        let result = transcribeRawResult ?? transcriptionResult
        return try result.get()
    }

    // MARK: - Test Helpers

    func reset() {
        transcriptionResult = .success("Mock transcription")
        transcribeRawResult = nil
        lastAudioURL = nil
        lastProvider = nil
        lastModel = nil
        callCount = 0
        transcribeRawCallCount = 0
        simulatedDelay = 0
    }

    func setSuccess(_ text: String) {
        transcriptionResult = .success(text)
    }

    func setFailure(_ error: Error) {
        transcriptionResult = .failure(error)
    }
}
