import CoreAudio
import XCTest
@testable import AudioWhisper

/// Fake HAL. Records what was asked of the device and lets each call be failed
/// independently, so the manager's error handling is reachable.
private final class FakeVolumeController: AudioDeviceVolumeControlling, @unchecked Sendable {
    var deviceID: AudioDeviceID = 42
    var currentVolume: Float32 = 0.35
    var volumeControlAvailable = true

    var failDeviceLookup = false
    var failGetVolume = false
    var failSetVolume = false
    /// `setInputVolume` returning false models a device that reports
    /// `kAudioHardwareUnsupportedOperationError` rather than throwing.
    var setVolumeReturnsFalse = false

    private(set) var setVolumeCalls: [Float32] = []
    private(set) var getVolumeCallCount = 0

    func defaultInputDeviceID() async throws -> AudioDeviceID {
        if failDeviceLookup { throw VolumeError.deviceNotFound }
        return deviceID
    }

    func hasVolumeControl(deviceID: AudioDeviceID) async throws -> Bool {
        volumeControlAvailable
    }

    func inputVolume(deviceID: AudioDeviceID) async throws -> Float32 {
        getVolumeCallCount += 1
        if failGetVolume { throw VolumeError.getVolumeFailed }
        return currentVolume
    }

    @discardableResult
    func setInputVolume(deviceID: AudioDeviceID, volume: Float32) async throws -> Bool {
        if failSetVolume { throw VolumeError.setVolumeFailed }
        setVolumeCalls.append(volume)
        if setVolumeReturnsFalse { return false }
        currentVolume = volume
        return true
    }
}

/// The boost/restore state machine in `MicrophoneVolumeManager`.
///
/// Audit item D3. This sat at 6.4% coverage (235 missed lines) behind a test
/// file named after it. The barrier was never laziness: every method called
/// straight into the Core Audio HAL against the machine's real default input
/// device, so a test would have changed the developer's microphone volume for
/// real and would have had no device at all on CI.
///
/// With the HAL behind `AudioDeviceVolumeControlling`, the part that can
/// actually be wrong is testable. The failure mode is concrete: if restore does
/// not fire, or state is not cleaned up after a failed HAL call, the user's
/// microphone is left pinned at 100% after they stop recording.
@MainActor
final class MicrophoneVolumeStateMachineTests: XCTestCase {

    private var hal: FakeVolumeController!
    private var manager: MicrophoneVolumeManager!

    override func setUp() async throws {
        try await super.setUp()
        hal = FakeVolumeController()
        manager = MicrophoneVolumeManager(controller: hal)
    }

    // MARK: - Boost

    func testBoostSetsVolumeToMaximum() async {
        let ok = await manager.boostMicrophoneVolume()

        XCTAssertTrue(ok)
        XCTAssertEqual(hal.setVolumeCalls, [1.0])
    }

    /// Boosting twice must not overwrite the remembered original with the
    /// already-boosted value — that is how a user ends up permanently at 100%.
    func testDoubleBoostDoesNotClobberTheRememberedOriginal() async {
        hal.currentVolume = 0.35

        let first = await manager.boostMicrophoneVolume()
        let second = await manager.boostMicrophoneVolume()
        XCTAssertTrue(first)
        XCTAssertTrue(second, "second boost is a no-op success")

        XCTAssertEqual(hal.setVolumeCalls, [1.0], "the device must be set once, not twice")
        XCTAssertEqual(hal.getVolumeCallCount, 1, "the original must be read once")

        await manager.restoreMicrophoneVolume()
        XCTAssertEqual(hal.setVolumeCalls, [1.0, 0.35], "must restore the pre-boost volume")
    }

    func testBoostFailsCleanlyWhenNoInputDevice() async {
        hal.failDeviceLookup = true

        let ok = await manager.boostMicrophoneVolume()

        XCTAssertFalse(ok)
        XCTAssertTrue(hal.setVolumeCalls.isEmpty)
    }

    func testBoostFailsCleanlyWhenCurrentVolumeCannotBeRead() async {
        hal.failGetVolume = true

        let ok = await manager.boostMicrophoneVolume()

        XCTAssertFalse(ok, "without the original volume there is nothing to restore to")
        XCTAssertTrue(hal.setVolumeCalls.isEmpty, "must not boost what it cannot restore")
    }

    /// A device that cannot be boosted must not be recorded as boosted —
    /// otherwise restore would later write a volume the device never had.
    func testDeviceThatRefusesTheBoostIsNotMarkedBoosted() async {
        hal.setVolumeReturnsFalse = true

        let ok = await manager.boostMicrophoneVolume()
        XCTAssertFalse(ok)

        hal.setVolumeReturnsFalse = false
        await manager.restoreMicrophoneVolume()

        XCTAssertEqual(hal.setVolumeCalls, [1.0],
                       "restore must be a no-op after a boost that did not take effect")
    }

    // MARK: - Restore

    func testRestorePutsTheOriginalVolumeBack() async {
        hal.currentVolume = 0.42
        _ = await manager.boostMicrophoneVolume()

        await manager.restoreMicrophoneVolume()

        XCTAssertEqual(hal.setVolumeCalls, [1.0, 0.42])
        XCTAssertEqual(hal.currentVolume, 0.42)
    }

    func testRestoreWithoutABoostIsANoOp() async {
        await manager.restoreMicrophoneVolume()
        XCTAssertTrue(hal.setVolumeCalls.isEmpty)
    }

    func testRestoreTwiceOnlyWritesOnce() async {
        _ = await manager.boostMicrophoneVolume()

        await manager.restoreMicrophoneVolume()
        await manager.restoreMicrophoneVolume()

        XCTAssertEqual(hal.setVolumeCalls, [1.0, 0.35],
                       "the second restore must not re-write the volume")
    }

    /// The `defer`-like cleanup: even when the HAL rejects the restore write,
    /// the manager must drop its boosted state rather than believing forever
    /// that it still owes a restore.
    func testStateIsClearedEvenWhenTheRestoreWriteFails() async {
        _ = await manager.boostMicrophoneVolume()
        hal.failSetVolume = true

        await manager.restoreMicrophoneVolume()

        // A subsequent boost must behave as a fresh one, which it only can if
        // the failed restore still cleared `isVolumeBoosted`.
        hal.failSetVolume = false
        hal.currentVolume = 0.7
        let ok = await manager.boostMicrophoneVolume()

        XCTAssertTrue(ok)
        XCTAssertEqual(hal.getVolumeCallCount, 2, "a fresh boost must re-read the original")
    }

    /// A full record → stop cycle must leave the device exactly as it was found.
    func testBoostRestoreCycleIsVolumeNeutral() async {
        hal.currentVolume = 0.6
        let before = hal.currentVolume

        _ = await manager.boostMicrophoneVolume()
        await manager.restoreMicrophoneVolume()

        XCTAssertEqual(hal.currentVolume, before,
                       "the user's microphone volume must survive a recording session")
    }

    // MARK: - Availability

    func testVolumeControlAvailabilityReflectsTheDevice() async {
        hal.volumeControlAvailable = true
        let available = await manager.isVolumeControlAvailable()
        XCTAssertTrue(available)

        hal.volumeControlAvailable = false
        let unavailable = await manager.isVolumeControlAvailable()
        XCTAssertFalse(unavailable)
    }

    func testVolumeControlIsUnavailableWhenTheDeviceLookupFails() async {
        hal.failDeviceLookup = true
        let available = await manager.isVolumeControlAvailable()
        XCTAssertFalse(available)
    }
}
