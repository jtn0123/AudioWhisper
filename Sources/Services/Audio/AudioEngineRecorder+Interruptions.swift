import Accelerate
import AppKit
import AVFoundation
import Foundation
import os.log

private let interruptionLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "AudioWhisper",
    category: "AudioEngineRecorder"
)

// Sleep / engine-configuration-change interruption handling (H4).
// Extracted from the main type to keep its body under SwiftLint's length cap.
extension AudioEngineRecorder {

    func installInterruptionObservers() {
        removeInterruptionObservers()

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleSleepInterruption()
            }
        }

        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleEngineConfigurationChange()
            }
        }
    }

    func removeInterruptionObservers() {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            sleepObserver = nil
        }
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
    }

    func handleSleepInterruption() {
        guard isRecording else { return }
        interruptionLogger.warning("System will sleep mid-recording - stopping cleanly")
        _ = stopRecording()
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
    }

    func handleEngineConfigurationChange() {
        guard isRecording, let engine = audioEngine else { return }
        if !engine.isRunning {
            interruptionLogger.error(
                "Audio engine stopped after configuration change - recording interrupted"
            )
            cancelRecording()
            NotificationCenter.default.post(name: .recordingStartFailed, object: nil)
        }
    }

    nonisolated func downsampleForDisplay(_ samples: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0, samples.count > targetCount else { return samples }

        let chunkSize = samples.count / targetCount
        var result = [Float](repeating: 0, count: targetCount)

        for chunkIndex in 0..<targetCount {
            let startIndex = chunkIndex * chunkSize
            let endIndex = min(startIndex + chunkSize, samples.count)
            let chunk = Array(samples[startIndex..<endIndex])
            var rms: Float = 0
            vDSP_rmsqv(chunk, 1, &rms, vDSP_Length(chunk.count))
            result[chunkIndex] = rms
        }

        return result
    }
}
