import Foundation
import Combine

/// Protocol defining the interface for audio recording services.
/// Both `AudioRecorder` (meter-based) and `AudioEngineRecorder` (sample-based) conform to this.
@MainActor
protocol AudioRecording: AnyObject, ObservableObject {
    /// Whether recording is currently active
    var isRecording: Bool { get }

    /// Normalized audio level (0.0 to 1.0) for basic visualization
    var audioLevel: Float { get }

    /// Raw waveform samples for detailed visualization (empty for classic mode)
    var waveformSamples: [Float] { get }

    /// Frequency band levels from FFT analysis (8 bands, each 0.0 to 1.0)
    var frequencyBands: [Float] { get }

    /// When the current recording session started
    var currentSessionStart: Date? { get }

    /// Duration of the last completed recording
    var lastRecordingDuration: TimeInterval? { get }

    /// Start recording audio
    /// - Returns: `true` if recording started successfully
    func startRecording() -> Bool

    /// Stop recording and return the audio file URL
    /// - Returns: URL to the recorded audio file, or `nil` if no recording was active
    func stopRecording() -> URL?

    /// Cancel the current recording without saving
    func cancelRecording()

    /// Clean up temporary recording files
    func cleanupRecording()
}

/// Default implementations for waveform data (for backward compatibility)
extension AudioRecording {
    var waveformSamples: [Float] { [] }
    var frequencyBands: [Float] { Array(repeating: 0, count: 8) }
}
