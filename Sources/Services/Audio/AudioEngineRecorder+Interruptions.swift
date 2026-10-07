import Accelerate
import AppKit
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
        let captureID = recordingSessionID

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recordingSessionID == captureID else { return }
                self.handleSleepInterruption()
            }
        }

        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.recordingSessionID == captureID else { return }
                self.handleEngineConfigurationChange()
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
        let id = recordingSessionID
        let audio = stopRecording()
        if let id {
            NotificationCenter.default.post(
                name: .recordingInterrupted, object: self,
                userInfo: ["event": RecordingInterruption.finished(
                    sessionID: id, audio: audio, duration: lastRecordingDuration)]
            )
        } else if let audio {
            try? FileManager.default.removeItem(at: audio)
        }
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
    }

    func handleEngineConfigurationChange() {
        guard isRecording, let engine = audioEngine else { return }
        if !engine.isRunning {
            interruptionLogger.error(
                "Audio engine stopped after configuration change - recording interrupted"
            )
            let id = recordingSessionID
            cancelRecording()
            if let id {
                NotificationCenter.default.post(
                    name: .recordingInterrupted, object: self,
                    userInfo: ["event": RecordingInterruption.failed(
                        sessionID: id,
                        message: "The microphone stopped after an input change. Check your input and record again.")]
                )
            }
            NotificationCenter.default.post(name: .recordingStartFailed, object: nil)
        }
    }

    nonisolated func downsampleForDisplay(_ samples: [Float], targetCount: Int) -> [Float] {
        guard targetCount > 0, samples.count > targetCount else { return samples }

        let chunkSize = samples.count / targetCount
        var result = [Float](repeating: 0, count: targetCount)

        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for chunkIndex in 0..<targetCount {
                let startIndex = chunkIndex * chunkSize
                let endIndex = min(startIndex + chunkSize, buffer.count)
                var rms: Float = 0
                vDSP_rmsqv(base.advanced(by: startIndex), 1, &rms, vDSP_Length(endIndex - startIndex))
                result[chunkIndex] = rms
            }
        }

        return result
    }
}
