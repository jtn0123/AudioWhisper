import CoreAudio
import Foundation

/// The Core Audio HAL operations `MicrophoneVolumeManager` needs.
///
/// Audit item D3. `MicrophoneVolumeManager` sat at 6.4% coverage (235 missed
/// lines) with a test file named after it. The report called that "no rendering
/// excuse" — true, but the real barrier was never laziness: every method reached
/// straight into `AudioObjectGetPropertyData` against the machine's *actual*
/// default input device. A test could not run without changing the developer's
/// microphone volume for real, and on CI there is no input device at all.
///
/// Splitting the HAL calls behind this protocol separates the two things that
/// were tangled:
///
///   * **The HAL binding** (`CoreAudioDeviceVolumeController`) — thin, hardware-
///     bound, and still untested. Nothing is gained by pretending otherwise.
///   * **The boost/restore state machine** (`MicrophoneVolumeManager`) — which
///     volume gets remembered, whether restore actually fires, and whether state
///     is cleaned up when the HAL call fails. That is ordinary logic with a real
///     failure mode: get it wrong and the user's microphone is left pinned at
///     100% after recording. It is now testable.
internal protocol AudioDeviceVolumeControlling: Sendable {
    func defaultInputDeviceID() async throws -> AudioDeviceID
    func hasVolumeControl(deviceID: AudioDeviceID) async throws -> Bool
    func inputVolume(deviceID: AudioDeviceID) async throws -> Float32
    @discardableResult
    func setInputVolume(deviceID: AudioDeviceID, volume: Float32) async throws -> Bool
}
