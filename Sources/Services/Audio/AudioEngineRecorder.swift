import Accelerate
import AppKit
import AVFoundation
import Combine
import Foundation
import QuartzCore
import os.log

/// Audio recorder using AVAudioEngine for real-time sample access.
/// Provides raw waveform samples and frequency data for enhanced visualizations.
@MainActor
final class AudioEngineRecorder: NSObject, ObservableObject, AudioRecording {
    // MARK: - Published Properties

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published private(set) var waveformSamples: [Float] = []
    @Published private(set) var frequencyBands: [Float] = Array(repeating: 0, count: 8)

    // MARK: - Recording State

    private(set) var currentSessionStart: Date?
    private(set) var lastRecordingDuration: TimeInterval?

    // MARK: - Audio Engine

    var audioEngine: AVAudioEngine?
    // audioFile is read on the audio thread (in processAudioBuffer) and mutated on the main thread.
    // Mutations always happen after removeTap + engine.stop (in stopEngine), so the audio thread
    // cannot observe a torn-down file reference while the tap is still firing.
    private nonisolated(unsafe) var audioFile: AVAudioFile?
    private var recordingURL: URL?

    // MARK: - Processing

    private let fftProcessor: FFTProcessor?
    private nonisolated(unsafe) var sampleBuffer: [Float] = []  // Access under sampleBufferLock (audio thread + main)
    private let sampleBufferSize = 2048
    private let dateProvider: () -> Date
    // Guards sampleBuffer, _writeErrorCount, _writeSuccessCount, _framesWritten, _lastLevelPublishTime.
    private let sampleBufferLock = NSLock()
    private nonisolated(unsafe) var _writeErrorCount = 0  // Write errors for diagnostics (under sampleBufferLock)
    private nonisolated(unsafe) var _writeSuccessCount = 0  // Successful buffer writes (under sampleBufferLock)
    private nonisolated(unsafe) var _framesWritten: Int64 = 0  // Total frames written (under sampleBufferLock)

    // MARK: - Level Meter Throttle (60 Hz)
    // Audio callbacks fire much faster than SwiftUI can render (e.g. ~86 Hz at 16 kHz / 1024-frame buffers,
    // higher at 44.1/48 kHz). Throttle published-level updates to ~60 Hz to avoid wasted MainActor hops
    // and unnecessary SwiftUI invalidations. Uses CACurrentMediaTime() — a monotonic clock that's
    // immune to wall-clock jumps.
    nonisolated private static let levelPublishInterval: TimeInterval = 1.0 / 60.0
    private nonisolated(unsafe) var _lastLevelPublishTime: TimeInterval = 0  // Access under sampleBufferLock

    // MARK: - Volume Management

    private let volumeManager: MicrophoneVolumeManaging

    // MARK: - Interruption Observers
    // Registered for the lifetime of a recording session (start → stop/cancel)
    // so we can detect machine sleep and AVAudioEngine config/route changes that
    // silently truncate recordings. Cleared in `stopEngine` and `deinit`.
    var sleepObserver: NSObjectProtocol?
    var configChangeObserver: NSObjectProtocol?

    // MARK: - Initialization

    override init() {
        self.fftProcessor = FFTProcessor()
        self.volumeManager = MicrophoneVolumeManager.shared
        self.dateProvider = { Date() }
        super.init()
    }

    init(
        volumeManager: MicrophoneVolumeManaging? = nil,
        dateProvider: @escaping () -> Date = { Date() }
    ) {
        // A5: resolved in the body rather than as a default argument.
        // Default-argument expressions are evaluated in the CALLER's
        // isolation, so referencing a @MainActor `.shared` there warns
        // ("error in the Swift 6 language mode") even though this type is
        // itself @MainActor. Same pattern DashboardHomeView already uses.

        self.fftProcessor = FFTProcessor()
        self.volumeManager = volumeManager ?? MicrophoneVolumeManager.shared
        self.dateProvider = dateProvider
        super.init()
    }

    deinit {
        // Safety-net cleanup if the recorder is dropped mid-recording without a
        // balanced stop/cancel: stop the engine, remove the tap, close/flush the
        // open file (niling the AVAudioFile flushes it), and restore boosted mic
        // volume. `deinit` may access these MainActor-isolated stored properties
        // directly (it shares the isolation domain); AVAudioEngine teardown is
        // safe here. `restoreMicrophoneVolume` is idempotent when nothing boosted.
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        audioFile = nil
        if AppDefaults.autoBoostMicrophoneVolume {
            let manager = volumeManager
            Task { await manager.restoreMicrophoneVolume() }
        }
    }

    // MARK: - AudioRecording Protocol

    func startRecording() -> Bool {
        // Check permission via PermissionManager (single source of truth)
        guard PermissionManager.shared.microphonePermissionState == .granted else {
            return false
        }

        // Prevent re-entrancy
        guard audioEngine == nil else {
            return false
        }

        // Skip real audio hardware operations in test environment to prevent errors
        if AppEnvironment.isRunningTests {
            return false
        }

        // Boost microphone volume if enabled.
        // Dispatched AFTER the early-return checks above so the boost only happens
        // when a real recording session actually begins — otherwise the matching
        // restore (in stop/cancel) would never fire and the boost would stick.
        if AppDefaults.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.boostMicrophoneVolume()
            }
        }

        // Create recording URL
        let tempPath = FileManager.default.temporaryDirectory
        let timestamp = dateProvider().timeIntervalSince1970
        let audioFilename = tempPath.appendingPathComponent("recording_\(timestamp).m4a")
        recordingURL = audioFilename

        do {
            // Set up audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Map the FFT processor to the device's actual sample rate. The tap runs
            // at the device rate (often 48 kHz), not the 44.1 kHz default — without
            // this, frequency bands are mislabeled (Hz→bin mapping uses sampleRate).
            fftProcessor?.updateSampleRate(Float(inputFormat.sampleRate))

            // Create output file for recording.
            // The channel count MUST match the input tap buffer's channel count, or
            // every `audioFile.write(from:)` throws (channel-count mismatch) and the
            // recording ends up empty on stereo input devices.
            let outputSettings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: Int(inputFormat.channelCount),
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioFile = try AVAudioFile(
                forWriting: audioFilename,
                settings: outputSettings
            )

            // Install tap for real-time audio access
            let bufferSize = AVAudioFrameCount(1024)
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
                self?.processAudioBuffer(buffer)
            }

            // Start the engine
            try engine.start()

            audioEngine = engine
            currentSessionStart = dateProvider()
            lastRecordingDuration = nil
            sampleBufferLock.lock()
            _writeErrorCount = 0  // Reset error count for new session
            _writeSuccessCount = 0  // Reset success count for new session
            _framesWritten = 0  // Reset frame counter for new session
            _lastLevelPublishTime = 0  // Allow the first level publish in this session to fire immediately
            sampleBufferLock.unlock()
            isRecording = true

            installInterruptionObservers()

            return true

        } catch {
            Logger.audioEngineRecorder.error("Failed to start engine recording: \(error.localizedDescription)")

            // Clear recordingURL to prevent orphaned file reference
            recordingURL = nil

            // Restore volume if recording failed
            if AppDefaults.autoBoostMicrophoneVolume {
                Task {
                    await volumeManager.restoreMicrophoneVolume()
                }
            }

            // Recheck permissions
            PermissionManager.shared.checkPermissionState()
            return false
        }
    }

    func stopRecording() -> URL? {
        let now = dateProvider()
        let sessionDuration = currentSessionStart.map { now.timeIntervalSince($0) }
        lastRecordingDuration = sessionDuration
        currentSessionStart = nil

        // Snapshot write diagnostics captured during the recording.
        sampleBufferLock.lock()
        let errorCount = _writeErrorCount
        let successCount = _writeSuccessCount
        let framesWritten = _framesWritten
        sampleBufferLock.unlock()
        if errorCount > 0 {
            Logger.audioEngineRecorder.warning("Recording had \(errorCount) audio buffer write errors - audio may be incomplete")
        }

        stopEngine()

        // Restore microphone volume if it was boosted
        if AppDefaults.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }

        isRecording = false
        clearVisualizationData()

        // A recording is only usable if real audio frames were captured and at
        // least one buffer was written successfully. If every write failed (e.g.
        // a format mismatch) or no frames landed, the file is empty/corrupt — return
        // nil so the caller's `guard let` rejects it instead of transcribing garbage.
        guard framesWritten > 0, successCount > 0 else {
            Logger.audioEngineRecorder.error("Recording unusable (\(framesWritten)f/\(successCount)ok/\(errorCount)err) - discarded")
            cleanupRecording()
            return nil
        }

        return recordingURL
    }

    func cancelRecording() {
        currentSessionStart = nil
        lastRecordingDuration = nil

        stopEngine()

        // Restore microphone volume
        if AppDefaults.autoBoostMicrophoneVolume {
            Task {
                await volumeManager.restoreMicrophoneVolume()
            }
        }

        isRecording = false
        clearVisualizationData()
        cleanupRecording()
    }

    func cleanupRecording() {
        guard let url = recordingURL else { return }

        currentSessionStart = nil
        lastRecordingDuration = nil

        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            // Skip logging in tests to reduce console noise
            if !AppEnvironment.isRunningTests {
                Logger.audioEngineRecorder.error("Failed to cleanup recording file: \(error.localizedDescription)")
            }
        }

        recordingURL = nil
    }

    // MARK: - Private Methods

    private func stopEngine() {
        removeInterruptionObservers()
        if let engine = audioEngine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        audioEngine = nil
        // AVAudioFile flushes buffers on dealloc. Explicitly nil to trigger
        // immediate deallocation and flush before caller processes the file.
        // Note: If there are other references, dealloc may be delayed.
        audioFile = nil
    }

    // MARK: - Interruption Handling (H4)
    //
    // Without these observers, lid-close or input-device-change mid-recording
    // would silently stop the engine while `isRecording == true`, truncating
    // the recording without telling the caller. We treat sleep as a graceful
    // user-stop (commit what we have) and an engine-config change as an
    // interruption surfaced through `.recordingStartFailed`.

    private func clearVisualizationData() {
        audioLevel = 0.0
        waveformSamples = []
        frequencyBands = Array(repeating: 0, count: 8)
        // Use lock for thread-safe sampleBuffer access
        sampleBufferLock.lock()
        sampleBuffer.removeAll()
        sampleBufferLock.unlock()
    }

    /// Called on the AVAudioEngine audio thread (NOT main). Stays `nonisolated` so the audio
    /// path does no MainActor hops for the data path itself — only the throttled level/waveform
    /// publish hops to main.
    nonisolated private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        // Convert to mono by averaging channels
        var monoSamples = [Float](repeating: 0, count: frameLength)

        if channelCount == 1 {
            // Already mono
            monoSamples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        } else {
            // Average channels
            for frameIndex in 0..<frameLength {
                var sum: Float = 0
                for channel in 0..<channelCount {
                    sum += channelData[channel][frameIndex]
                }
                monoSamples[frameIndex] = sum / Float(channelCount)
            }
        }

        // Write to file (on audio thread for performance)
        if let audioFile = audioFile {
            do {
                try audioFile.write(from: buffer)
                // Track successful writes + frames so stopRecording can tell whether
                // the recording is actually usable (thread-safe via sampleBufferLock).
                sampleBufferLock.lock()
                _writeSuccessCount += 1
                _framesWritten += Int64(frameLength)
                sampleBufferLock.unlock()
            } catch {
                // Track write errors for later reporting (thread-safe via sampleBufferLock)
                sampleBufferLock.lock()
                _writeErrorCount += 1
                let isFirstError = _writeErrorCount == 1
                sampleBufferLock.unlock()
                if isFirstError {
                    // Only log the first error to avoid log spam
                    Logger.audioEngineRecorder.error("Failed to write audio buffer: \(error.localizedDescription)")
                }
            }
        }

        // Use lock for thread-safe sampleBuffer access (called from audio thread)
        // This implements a bounded circular buffer pattern:
        // - Append new samples
        // - If buffer exceeds max size, remove oldest samples to maintain fixed size
        // - Maximum size is sampleBufferSize (2048 samples = ~128ms at 16kHz)
        // Also gates the level-meter publish to ~60 Hz under the same lock.
        let now = CACurrentMediaTime()
        sampleBufferLock.lock()
        sampleBuffer.append(contentsOf: monoSamples)
        let overflow = sampleBuffer.count - sampleBufferSize
        if overflow > 0 {
            // Use suffix to efficiently keep only the most recent samples
            sampleBuffer = Array(sampleBuffer.suffix(sampleBufferSize))
        }
        let currentBuffer = sampleBuffer
        let shouldPublish = (now - _lastLevelPublishTime) >= Self.levelPublishInterval
        if shouldPublish {
            _lastLevelPublishTime = now
        }
        sampleBufferLock.unlock()

        // Throttle the *publish* to 60 Hz. Buffer accumulation + file write above
        // are intentionally NOT throttled — we must never drop audio frames.
        guard shouldPublish else { return }

        // Calculate audio level and frequency bands (graceful fallback if FFT unavailable)
        let level = fftProcessor?.calculateLevel(from: monoSamples) ?? 0.0
        let bands = fftProcessor?.process(currentBuffer) ?? Array(repeating: 0, count: 8)

        // Downsample waveform for display (reduce to ~128 points)
        let displaySamples = downsampleForDisplay(currentBuffer, targetCount: 128)

        // Update published properties on main thread
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.audioLevel = level
            self.frequencyBands = bands
            self.waveformSamples = displaySamples
        }
    }

}

// MARK: - Logger Extension

private extension Logger {
    static let audioEngineRecorder = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AudioWhisper",
        category: "AudioEngineRecorder"
    )
}
