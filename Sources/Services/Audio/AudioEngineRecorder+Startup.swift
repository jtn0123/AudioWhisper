import AVFoundation
import CoreAudio
import Foundation

/// This inactive engine crosses the worker boundary once. Only the main actor
/// uses it after transfer; abandoned preparations never install taps or start.
struct PreparedAudioEngine: @unchecked Sendable {
    let engine: AVAudioEngine
    let inputNode: AVAudioInputNode
    let format: AVAudioFormat
    let device: AudioDeviceID

    static func make(routing: AudioInputRouting, selectedUID: String) throws -> Self {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        guard let unit = inputNode.audioUnit else { throw AudioInputError.unavailable }
        let device = try routing.prepare(selectedUID: selectedUID, unit: unit)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioInputError.invalidFormat }
        return Self(engine: engine, inputNode: inputNode, format: format, device: device)
    }
}

extension AudioEngineRecorder {
    func startRecordingAsync(sessionID: UUID) async -> Bool {
        guard canStartRecording() else { return false }
        let routing = inputRouting
        let selectedUID = AppDefaults.selectedMicrophone
        do {
            let prepared = try await hardwarePreparation.run {
                try PreparedAudioEngine.make(routing: routing, selectedUID: selectedUID)
            }
            guard !Task.isCancelled, audioEngine == nil,
                  PermissionManager.shared.microphonePermissionState == .granted else { return false }
            return startPreparedEngine(prepared, sessionID: sessionID)
        } catch {
            return failRecordingStart(error)
        }
    }
}
