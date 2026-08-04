import XCTest
@testable import AudioWhisper

final class MicrophoneVolumeManagerTests: IsolatedXCTestCase {
    // Deferred(D1): MicrophoneVolumeManager reads `autoBoostMicrophoneVolume`
    // from UserDefaults.standard. Once it accepts an injected UserDefaults,
    // route writes through a UUID-scoped suite and re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    override func tearDown() {
        // Clean up UserDefaults
        AppDefaults.defaults.removeObject(forKey: "autoBoostMicrophoneVolume")
        super.tearDown()
    }

    // MARK: - VolumeError Tests

    func testVolumeErrorDescriptions() {
        XCTAssertEqual(
            VolumeError.deviceNotFound.errorDescription,
            "Default input device not found"
        )
        XCTAssertEqual(
            VolumeError.getVolumeFailed.errorDescription,
            "Failed to get current volume"
        )
        XCTAssertEqual(
            VolumeError.setVolumeFailed.errorDescription,
            "Failed to set volume"
        )
        XCTAssertEqual(
            VolumeError.volumeControlNotSupported.errorDescription,
            "Volume control not supported for this device"
        )
    }

    // MARK: - UserDefaults Extension Tests

    func testAutoBoostMicrophoneVolumeUserDefaultsKeyGetDefault() {
        // Ensure key is not set
        AppDefaults.defaults.removeObject(forKey: "autoBoostMicrophoneVolume")

        // Default should be false
        XCTAssertFalse(AppDefaults.defaults.autoBoostMicrophoneVolume)
    }

    func testAutoBoostMicrophoneVolumeUserDefaultsKeySetTrue() {
        AppDefaults.defaults.autoBoostMicrophoneVolume = true
        XCTAssertTrue(AppDefaults.defaults.autoBoostMicrophoneVolume)
    }

    func testAutoBoostMicrophoneVolumeUserDefaultsKeySetFalse() {
        AppDefaults.defaults.autoBoostMicrophoneVolume = true
        AppDefaults.defaults.autoBoostMicrophoneVolume = false
        XCTAssertFalse(AppDefaults.defaults.autoBoostMicrophoneVolume)
    }

    // MARK: - Protocol Conformance Tests

    // MicrophoneVolumeManager.shared is main-actor isolated; reaching it from
    // this nonisolated test is an error under the Swift 6 language mode.
    @MainActor
    func testMicrophoneVolumeManagerConformsToProtocol() {
        let manager: MicrophoneVolumeManaging = MicrophoneVolumeManager.shared
        XCTAssertNotNil(manager)
    }
}

// MARK: - Mock for Protocol-Based Testing

/// Mock implementation of MicrophoneVolumeManaging for testing dependent code
private final class TestMicrophoneVolumeManagerMock: MicrophoneVolumeManaging {
    var boostCallCount = 0
    var restoreCallCount = 0
    var isVolumeControlAvailableResult = true
    var boostResult = true

    func boostMicrophoneVolume() async -> Bool {
        boostCallCount += 1
        return boostResult
    }

    func restoreMicrophoneVolume() async {
        restoreCallCount += 1
    }

    func isVolumeControlAvailable() async -> Bool {
        return isVolumeControlAvailableResult
    }

    func reset() {
        boostCallCount = 0
        restoreCallCount = 0
        isVolumeControlAvailableResult = true
        boostResult = true
    }
}

final class TestMicrophoneVolumeManagerMockTests: XCTestCase {

    func testMockTracksBoostCalls() async {
        let mock = TestMicrophoneVolumeManagerMock()

        _ = await mock.boostMicrophoneVolume()
        _ = await mock.boostMicrophoneVolume()

        XCTAssertEqual(mock.boostCallCount, 2)
    }

    func testMockTracksRestoreCalls() async {
        let mock = TestMicrophoneVolumeManagerMock()

        await mock.restoreMicrophoneVolume()

        XCTAssertEqual(mock.restoreCallCount, 1)
    }

    func testMockReturnsConfiguredBoostResult() async {
        let mock = TestMicrophoneVolumeManagerMock()

        mock.boostResult = false
        let result = await mock.boostMicrophoneVolume()

        XCTAssertFalse(result)
    }

    func testMockReturnsConfiguredVolumeControlAvailability() async {
        let mock = TestMicrophoneVolumeManagerMock()

        mock.isVolumeControlAvailableResult = false
        let result = await mock.isVolumeControlAvailable()

        XCTAssertFalse(result)
    }

    func testMockResetClearsState() async {
        let mock = TestMicrophoneVolumeManagerMock()

        _ = await mock.boostMicrophoneVolume()
        await mock.restoreMicrophoneVolume()
        mock.boostResult = false

        mock.reset()

        XCTAssertEqual(mock.boostCallCount, 0)
        XCTAssertEqual(mock.restoreCallCount, 0)
        XCTAssertTrue(mock.boostResult)
    }
}
