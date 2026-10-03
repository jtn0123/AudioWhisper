import CoreAudio
import XCTest
@testable import AudioWhisper

/// Tests for the Core Audio binding, using only an object ID that does not
/// exist.
///
/// That is deliberate. Pointing a test at the real default input device would
/// change the volume of whatever microphone the machine has (and CI runners may
/// have none). An unknown object ID makes every HAL call fail, which is exactly
/// the path worth checking: that each failure becomes the typed `VolumeError`
/// the boost/restore state machine in `MicrophoneVolumeManager` relies on,
/// rather than a garbage volume or a silent success.
final class CoreAudioDeviceVolumeControllerTests: XCTestCase {

    private let controller = CoreAudioDeviceVolumeController()
    private let missingDevice = AudioDeviceID(kAudioObjectUnknown)

    func testAMissingDeviceHasNoVolumeControl() async throws {
        let hasControl = try await controller.hasVolumeControl(deviceID: missingDevice)
        XCTAssertFalse(hasControl)
    }

    func testReadingTheVolumeOfAMissingDeviceThrowsGetVolumeFailed() async {
        do {
            let volume = try await controller.inputVolume(deviceID: missingDevice)
            XCTFail("expected getVolumeFailed, got volume \(volume)")
        } catch let error as VolumeError {
            XCTAssertEqual(error, .getVolumeFailed)
        } catch {
            XCTFail("expected VolumeError, got \(error)")
        }
    }

    func testSettingTheVolumeOfAMissingDeviceThrowsSetVolumeFailed() async {
        do {
            let applied = try await controller.setInputVolume(deviceID: missingDevice, volume: 0.5)
            XCTFail("expected setVolumeFailed, got \(applied)")
        } catch let error as VolumeError {
            XCTAssertEqual(error, .setVolumeFailed)
        } catch {
            XCTFail("expected VolumeError, got \(error)")
        }
    }

    /// Read-only. The machine either has a default input device or it does not
    /// (a CI runner may not); either way the answer must be an ID or the typed
    /// error, never some other failure.
    func testDefaultInputDeviceLookupReturnsAnIDOrDeviceNotFound() async {
        do {
            _ = try await controller.defaultInputDeviceID()
        } catch let error as VolumeError {
            XCTAssertEqual(error, .deviceNotFound)
        } catch {
            XCTFail("expected an ID or VolumeError.deviceNotFound, got \(error)")
        }
    }
}
