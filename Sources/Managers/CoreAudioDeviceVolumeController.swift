import CoreAudio

/// The real Core Audio HAL binding for microphone volume.
///
/// Audit item D3: lifted verbatim out of `MicrophoneVolumeManager` so the
/// boost/restore state machine could be tested without a physical input device.
/// This type is a thin translation of `AudioObjectGetPropertyData` /
/// `AudioObjectSetPropertyData` calls against the machine's actual default input
/// device; the logic worth testing was moved above it, not down here. Its tests
/// (`CoreAudioDeviceVolumeControllerTests`) use only a nonexistent object ID, so
/// they check the status-to-`VolumeError` mapping without touching a real
/// microphone's volume.
internal struct CoreAudioDeviceVolumeController: AudioDeviceVolumeControlling {
    func defaultInputDeviceID() async throws -> AudioDeviceID {
        return try await withCheckedThrowingContinuation { continuation in
            var deviceID: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            )

            if status == noErr {
                continuation.resume(returning: deviceID)
            } else {
                continuation.resume(throwing: VolumeError.deviceNotFound)
            }
        }
    }

    func hasVolumeControl(deviceID: AudioDeviceID) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let hasProperty = AudioObjectHasProperty(deviceID, &address)
            continuation.resume(returning: hasProperty)
        }
    }

    func inputVolume(deviceID: AudioDeviceID) async throws -> Float32 {
        return try await withCheckedThrowingContinuation { continuation in
            var volume: Float32 = 0.0
            var size = UInt32(MemoryLayout<Float32>.size)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &volume
            )

            if status == noErr {
                continuation.resume(returning: volume)
            } else {
                continuation.resume(throwing: VolumeError.getVolumeFailed)
            }
        }
    }

    @discardableResult
    func setInputVolume(deviceID: AudioDeviceID, volume: Float32) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            var newVolume = volume
            let size = UInt32(MemoryLayout<Float32>.size)

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let status = AudioObjectSetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                size,
                &newVolume
            )

            if status == noErr {
                continuation.resume(returning: true)
            } else if status == kAudioHardwareUnsupportedOperationError {
                // Some devices don't support volume control
                continuation.resume(returning: false)
            } else {
                continuation.resume(throwing: VolumeError.setVolumeFailed)
            }
        }
    }
}
