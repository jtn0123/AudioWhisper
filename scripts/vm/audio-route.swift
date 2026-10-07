// VM-only fixture routing. Run inside the disposable guest after installing
// BlackHole. Does not capture audio or request microphone access.
import CoreAudio
import Foundation

guard NSUserName() == "admin", FileManager.default.fileExists(atPath: "/Volumes/My Shared Files/qa") else {
    fputs("This routing helper is restricted to the prepared QA guest.\n", stderr)
    exit(1)
}

func require(_ status: OSStatus) {
    guard status == noErr else {
        fputs("CoreAudio routing failed: \(status)\n", stderr)
        exit(1)
    }
}

var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0
let system = AudioObjectID(kAudioObjectSystemObject)
require(AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size))
var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
require(AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices))
var loopback: AudioDeviceID?
for device in devices {
    var nameAddress = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var reference: Unmanaged<CFString>?
    var nameSize = UInt32(MemoryLayout.size(ofValue: reference))
    require(AudioObjectGetPropertyData(device, &nameAddress, 0, nil, &nameSize, &reference))
    guard let name = reference?.takeRetainedValue() else { continue }
    print("\(device): \(name)")
    if name as String == "BlackHole 2ch" { loopback = device }
}
guard var selected = loopback else {
    fputs("BlackHole 2ch is not installed in this guest\n", stderr)
    exit(1)
}
for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDefaultOutputDevice] {
    var routeAddress = AudioObjectPropertyAddress(
        mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    require(AudioObjectSetPropertyData(system, &routeAddress, 0, nil,
                                      UInt32(MemoryLayout<AudioDeviceID>.size), &selected))
}
print("Guest input and output routed to BlackHole 2ch")
