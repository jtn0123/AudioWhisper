// swiftlint:disable:next unused_import - verified required: removing it breaks the build (kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
import AudioToolbox
import CoreAudio

/// The Core Audio HAL operations `OutputDucker` needs.
protocol AudioOutputVolumeControlling {
    func defaultOutputDevice() -> AudioDeviceID?
    func uid(of device: AudioDeviceID) -> String?
    func device(withUID uid: String) -> AudioDeviceID?
    func volume(of device: AudioDeviceID) -> Float32?
    @discardableResult
    func setVolume(_ volume: Float32, of device: AudioDeviceID) -> Bool
}

/// The real binding, kept as thin as the microphone one.
///
/// Volume goes through the virtual main volume rather than the main element's
/// `kAudioDevicePropertyVolumeScalar`, because it also covers devices that
/// only have per-channel volume controls.
struct CoreAudioOutputVolumeController: AudioOutputVolumeControlling {
    func defaultOutputDevice() -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    func uid(of device: AudioDeviceID) -> String? {
        var uid: Unmanaged<CFString>?
        var address = Self.address(kAudioDevicePropertyDeviceUID)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr, let uid else { return nil }
        // The HAL hands back a retained string the caller must release.
        return uid.takeRetainedValue() as String
    }

    func device(withUID uid: String) -> AudioDeviceID? {
        var device = AudioDeviceID(kAudioObjectUnknown)
        var address = Self.address(kAudioHardwarePropertyTranslateUIDToDevice)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var qualifier = uid as CFString
        let status = withUnsafePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address,
                UInt32(MemoryLayout<CFString>.size), pointer, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    func volume(of device: AudioDeviceID) -> Float32? {
        var volume: Float32 = 0
        var address = Self.mainVolume
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr ? volume : nil
    }

    func setVolume(_ volume: Float32, of device: AudioDeviceID) -> Bool {
        var address = Self.mainVolume
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value = min(max(volume, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
    }

    private static let mainVolume = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
