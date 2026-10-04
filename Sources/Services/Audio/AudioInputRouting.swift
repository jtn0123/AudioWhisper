import AudioToolbox
import CoreAudio
import Foundation

enum AudioInputError: LocalizedError {
    case unavailable, routingFailed(OSStatus), invalidFormat

    var errorDescription: String? {
        switch self {
        case .unavailable: return "The selected microphone is unavailable. Connect it or choose another input in Preferences."
        case .routingFailed(let status): return "The selected microphone could not be connected (audio error \(status))."
        case .invalidFormat: return "The selected microphone has no usable audio input. Choose another input in Preferences."
        }
    }
}

/// Keeps the device selection and Audio Unit routing boundary independently
/// testable without opening hardware or changing the Mac's system default.
struct AudioInputRouting {
    var resolveDevice: (String) throws -> AudioDeviceID
    var applyDevice: (AudioDeviceID, AudioUnit) throws -> Void

    func prepare(selectedUID: String, unit: AudioUnit) throws -> AudioDeviceID {
        let device = try resolveDevice(selectedUID)
        guard device != kAudioObjectUnknown else { throw AudioInputError.unavailable }
        try applyDevice(device, unit)
        return device
    }

    static let live = Self(resolveDevice: resolveDeviceID, applyDevice: applyDeviceID)

    private static func resolveDeviceID(uid: String) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: uid.isEmpty ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status: OSStatus
        if uid.isEmpty {
            status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        } else {
            var qualifier = uid as CFString
            status = withUnsafePointer(to: &qualifier) { pointer in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject), &address,
                    UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
            }
        }
        guard status == noErr, device != kAudioObjectUnknown else { throw AudioInputError.unavailable }
        return device
    }

    private static func applyDeviceID(_ device: AudioDeviceID, unit: AudioUnit) throws {
        var selected = device
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
            &selected, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw AudioInputError.routingFailed(status) }
        var actual = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let readStatus = AudioUnitGetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &actual, &size)
        guard readStatus == noErr else { throw AudioInputError.routingFailed(readStatus) }
        guard actual == device else { throw AudioInputError.unavailable }
    }
}
