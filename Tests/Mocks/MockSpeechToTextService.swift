import Foundation
@testable import AudioWhisper

/// Protocol for speech-to-text service to enable mocking
protocol SpeechToTextServiceProtocol {
    func transcribeRaw(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel?) async throws -> String
    func transcribe(audioURL: URL) async throws -> String
    func transcribe(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel?) async throws -> String
}

/// Mock implementation for testing transcription flows
@MainActor
final class MockSpeechToTextService: SpeechToTextServiceProtocol {
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

    func transcribe(audioURL: URL) async throws -> String {
        callCount += 1
        lastAudioURL = audioURL

        if simulatedDelay > 0 {
            try? await Task.sleep(for: .milliseconds(Int(simulatedDelay * 1000)))
        }

        return try transcriptionResult.get()
    }

    func transcribe(audioURL: URL, provider: TranscriptionProvider, model: WhisperModel?) async throws -> String {
        callCount += 1
        lastAudioURL = audioURL
        lastProvider = provider
        lastModel = model

        if simulatedDelay > 0 {
            try? await Task.sleep(for: .milliseconds(Int(simulatedDelay * 1000)))
        }

        return try transcriptionResult.get()
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
