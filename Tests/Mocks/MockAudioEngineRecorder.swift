import Foundation
import Combine
@testable import AudioWhisper

/// Mock AudioEngineRecorder for testing recording operations
@MainActor
final class MockAudioEngineRecorder: ObservableObject, AudioRecording {
    // MARK: - Published Properties (AudioRecording Protocol)

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published private(set) var waveformSamples: [Float] = []
    @Published private(set) var frequencyBands: [Float] = Array(repeating: 0, count: 8)

    // MARK: - Recording State

    private(set) var currentSessionStart: Date?
    private(set) var lastRecordingDuration: TimeInterval?

    // MARK: - Call Tracking

    var startRecordingCalled = false
    var startRecordingCallCount = 0
    var stopRecordingCalled = false
    var stopRecordingCallCount = 0
    var cancelRecordingCalled = false
    var cancelRecordingCallCount = 0
    var cleanupRecordingCalled = false
    var cleanupRecordingCallCount = 0

    // MARK: - Behavior Configuration

    var startRecordingResult = true
    var stopRecordingResult: URL?
    var simulatedRecordingDuration: TimeInterval = 5.0

    // MARK: - Date Provider

    private let dateProvider: () -> Date

    // MARK: - Initialization

    init(dateProvider: @escaping () -> Date = { Date() }) {
        self.dateProvider = dateProvider
        // Create a temporary file URL for test purposes
        let tempPath = FileManager.default.temporaryDirectory
        let timestamp = dateProvider().timeIntervalSince1970
        stopRecordingResult = tempPath.appendingPathComponent("mock_recording_\(timestamp).m4a")
    }

    // MARK: - AudioRecording Protocol

    func startRecording() -> Bool {
        startRecordingCalled = true
        startRecordingCallCount += 1

        if startRecordingResult {
            isRecording = true
            currentSessionStart = dateProvider()
            lastRecordingDuration = nil
        }

        return startRecordingResult
    }

    func stopRecording() -> URL? {
        stopRecordingCalled = true
        stopRecordingCallCount += 1

        if let start = currentSessionStart {
            lastRecordingDuration = dateProvider().timeIntervalSince(start)
        } else {
            lastRecordingDuration = simulatedRecordingDuration
        }

        currentSessionStart = nil
        isRecording = false
        clearVisualizationData()

        return stopRecordingResult
    }

    func cancelRecording() {
        cancelRecordingCalled = true
        cancelRecordingCallCount += 1

        currentSessionStart = nil
        lastRecordingDuration = nil
        isRecording = false
        clearVisualizationData()
    }

    func cleanupRecording() {
        cleanupRecordingCalled = true
        cleanupRecordingCallCount += 1

        currentSessionStart = nil
        lastRecordingDuration = nil
    }

    // MARK: - Test Helpers

    func reset() {
        isRecording = false
        audioLevel = 0.0
        waveformSamples = []
        frequencyBands = Array(repeating: 0, count: 8)
        currentSessionStart = nil
        lastRecordingDuration = nil

        startRecordingCalled = false
        startRecordingCallCount = 0
        stopRecordingCalled = false
        stopRecordingCallCount = 0
        cancelRecordingCalled = false
        cancelRecordingCallCount = 0
        cleanupRecordingCalled = false
        cleanupRecordingCallCount = 0

        startRecordingResult = true
    }

    func simulateAudioLevel(_ level: Float) {
        audioLevel = level
    }

    func simulateWaveformData(_ samples: [Float]) {
        waveformSamples = samples
    }

    func simulateFrequencyBands(_ bands: [Float]) {
        guard bands.count == 8 else { return }
        frequencyBands = bands
    }

    private func clearVisualizationData() {
        audioLevel = 0.0
        waveformSamples = []
        frequencyBands = Array(repeating: 0, count: 8)
    }
}
