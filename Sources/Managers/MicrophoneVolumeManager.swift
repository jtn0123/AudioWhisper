import Foundation
import CoreAudio
import os.log
import Observation

// Protocol for testing (bug regression tests)
internal protocol MicrophoneVolumeManaging {
    func boostMicrophoneVolume() async -> Bool
    func restoreMicrophoneVolume() async
    func isVolumeControlAvailable() async -> Bool
}

@Observable
@MainActor
internal class MicrophoneVolumeManager: MicrophoneVolumeManaging {
    static let shared = MicrophoneVolumeManager()

    private var originalVolume: Float32?
    private var audioDeviceID: AudioDeviceID?
    private var isVolumeBoosted = false

    /// The Core Audio binding. Defaults to the real HAL controller; tests
    /// substitute a fake so the boost/restore state machine can be exercised
    /// without touching the developer's microphone (audit item D3).
    private let controller: AudioDeviceVolumeControlling

    private init() {
        self.controller = CoreAudioDeviceVolumeController()
    }

    /// Test seam. Not `private` so tests can build an instance with a fake HAL;
    /// production always goes through `.shared`.
    init(controller: AudioDeviceVolumeControlling) {
        self.controller = controller
    }

    // MARK: - Public Interface

    /// Temporarily boost microphone volume to maximum (100%)
    func boostMicrophoneVolume() async -> Bool {
        guard !isVolumeBoosted else { return true }

        do {
            let deviceID = try await controller.defaultInputDeviceID()
            let currentVolume = try await controller.inputVolume(deviceID: deviceID)

            // Store original volume and device for restoration
            originalVolume = currentVolume
            audioDeviceID = deviceID

            // Set volume to maximum
            let success = try await controller.setInputVolume(deviceID: deviceID, volume: 1.0)
            if success {
                isVolumeBoosted = true
            }

            return success
        } catch {
            Logger.microphoneVolume.error("Failed to boost microphone volume: \(error.localizedDescription)")
            return false
        }
    }

    /// Restore microphone volume to its original level
    func restoreMicrophoneVolume() async {
        guard isVolumeBoosted,
              let originalVolume = originalVolume,
              let deviceID = audioDeviceID else {
            return
        }

        do {
            _ = try await controller.setInputVolume(deviceID: deviceID, volume: originalVolume)
        } catch {
            Logger.microphoneVolume.error("Failed to restore microphone volume: \(error.localizedDescription)")
        }

        // Clean up state regardless of success
        self.originalVolume = nil
        self.audioDeviceID = nil
        isVolumeBoosted = false
    }

    /// Check if microphone volume control is available
    func isVolumeControlAvailable() async -> Bool {
        do {
            let deviceID = try await controller.defaultInputDeviceID()
            return try await controller.hasVolumeControl(deviceID: deviceID)
        } catch {
            return false
        }
    }

    // MARK: - Core Audio Implementation

    // MARK: - Alternative Implementation for USB/External Microphones

}

// MARK: - Error Types

internal enum VolumeError: LocalizedError {
    case deviceNotFound
    case getVolumeFailed
    case setVolumeFailed
    case volumeControlNotSupported

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:
            return "Default input device not found"
        case .getVolumeFailed:
            return "Failed to get current volume"
        case .setVolumeFailed:
            return "Failed to set volume"
        case .volumeControlNotSupported:
            return "Volume control not supported for this device"
        }
    }
}

// MARK: - Extension for UserDefaults Key

internal extension UserDefaults {
    var autoBoostMicrophoneVolume: Bool {
        get { bool(forKey: "autoBoostMicrophoneVolume") }
        set { set(newValue, forKey: "autoBoostMicrophoneVolume") }
    }
}
