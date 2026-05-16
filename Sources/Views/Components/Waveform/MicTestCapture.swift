import Accelerate
import AVFoundation
import Foundation
import os.log

// MARK: - MicTestState

/// State of the live mic test in the Visuals tab.
internal enum MicTestState: Equatable {
    case off
    case live
    case denied
    case error(String)
}

// MARK: - MicTestCapture

/// Captures live microphone audio for the "Test with my voice" banner and
/// feeds the derived level / samples / bands into a `LivePreviewSampler`.
///
/// Nothing is recorded or persisted — capture is visualization-only. The
/// engine + mic are released as soon as the test is stopped or fails.
@MainActor
final class MicTestCapture: ObservableObject {
    // MARK: - Published State

    @Published private(set) var state: MicTestState = .off
    @Published private(set) var level: Float = 0
    @Published private(set) var speaking: Bool = false

    // MARK: - Dependencies

    private weak var sampler: LivePreviewSampler?

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine?
    private let fftProcessor = FFTProcessor()

    /// Smoothed audio level — mutated on the audio thread, read for publishing.
    private nonisolated(unsafe) var smoothedLevel: Float = 0
    private let stateLock = NSLock()

    // MARK: - Lifecycle

    init(sampler: LivePreviewSampler) {
        self.sampler = sampler
    }

    deinit {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
    }

    // MARK: - Control

    /// Begin (or retry) live mic capture, requesting permission as needed.
    func start() {
        guard state != .live else { return }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginCapture()
        case .denied, .restricted:
            state = .denied
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if granted {
                        self.beginCapture()
                    } else {
                        self.state = .denied
                    }
                }
            }
        @unknown default:
            state = .error("permission status unknown")
        }
    }

    /// Stop capture, release the mic, and return the sampler to synthetic mode.
    func stop() {
        teardownEngine()
        smoothedLevel = 0
        level = 0
        speaking = false
        if state == .live { state = .off }
        sampler?.setMicMode(false)
    }

    // MARK: - Private

    private func beginCapture() {
        guard audioEngine == nil else { return }

        // Real audio hardware is unavailable / undesirable under tests.
        if AppEnvironment.isRunningTests {
            state = .error("test environment")
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            state = .error("no input device")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.handleBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            Logger.micTest.error("Failed to start mic test engine: \(error.localizedDescription)")
            state = .error(error.localizedDescription)
            return
        }

        audioEngine = engine
        sampler?.setMicMode(true)
        state = .live
    }

    private func teardownEngine() {
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
    }

    /// Called on the AVAudioEngine audio thread.
    nonisolated private func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let mono = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        // RMS level — amplified + smoothed per the design spec.
        var rms: Float = 0
        vDSP_rmsqv(mono, 1, &rms, vDSP_Length(frameLength))
        let target = max(0.05, min(1, rms * 5))
        let smooth = smoothedLevel * 0.55 + target * 0.45
        smoothedLevel = smooth

        // 64 time-domain samples scaled by 0.9.
        let samples = Self.downsample(mono, count: 64).map { $0 * 0.9 }

        // 8 frequency bands, ignoring the top ~35% of the range as noise.
        let rawBands = fftProcessor?.process(mono) ?? Array(repeating: 0, count: 8)
        let bands = rawBands.map { max(0.05, min(1, $0 * 1.8)) }

        let isSpeaking = smooth > 0.22

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.level = smooth
            self.speaking = isSpeaking
            self.sampler?.publishMicFrame(level: smooth, samples: samples, bands: bands)
        }
    }

    /// Average-pool `source` down to `count` evenly-spaced samples.
    nonisolated private static func downsample(_ source: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        guard source.count > count else {
            return source + Array(repeating: 0, count: count - source.count)
        }
        let chunk = source.count / count
        return (0..<count).map { index in
            let start = index * chunk
            let end = min(start + chunk, source.count)
            var sum: Float = 0
            for sampleIndex in start..<end { sum += source[sampleIndex] }
            return sum / Float(max(1, end - start))
        }
    }
}

// MARK: - Logger Extension

private extension Logger {
    static let micTest = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AudioWhisper",
        category: "MicTestCapture"
    )
}
