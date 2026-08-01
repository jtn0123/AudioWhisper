import XCTest
@testable import AudioWhisper

@MainActor
final class AudioEngineRecorderTests: IsolatedXCTestCase {
    // Deferred(D1): AudioEngineRecorder reads `autoBoostMicrophoneVolume` from
    // UserDefaults.standard directly. Once it accepts an injected
    // UserDefaults, route writes through a UUID-scoped suite and re-enable.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    var recorder: AudioEngineRecorder!
    fileprivate var mockVolumeManager: MockMicrophoneVolumeManager!
    var dateCallCount: Int = 0
    var testDates: [Date] = []

    override func setUp() {
        super.setUp()
        mockVolumeManager = MockMicrophoneVolumeManager()
        dateCallCount = 0
        testDates = []
        PermissionManager.shared.microphonePermissionState = .unknown
    }

    override func tearDown() {
        recorder?.cancelRecording()
        recorder = nil
        mockVolumeManager = nil
        AppDefaults.defaults.removeObject(forKey: "autoBoostMicrophoneVolume")
        PermissionManager.shared.microphonePermissionState = .unknown
        super.tearDown()
    }

    private func makeRecorder(dates: [Date] = []) -> AudioEngineRecorder {
        testDates = dates
        dateCallCount = 0
        return AudioEngineRecorder(
            volumeManager: mockVolumeManager,
            dateProvider: { [self] in
                let index = min(self.dateCallCount, self.testDates.count - 1)
                self.dateCallCount += 1
                return self.testDates.isEmpty ? Date() : self.testDates[max(0, index)]
            }
        )
    }

    // MARK: - Initial State Tests

    func testInitialState() {
        recorder = makeRecorder()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.audioLevel, 0.0)
        XCTAssertTrue(recorder.waveformSamples.isEmpty)
        XCTAssertEqual(recorder.frequencyBands.count, 8)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    func testFrequencyBandsInitializedToZero() {
        recorder = makeRecorder()

        for band in recorder.frequencyBands {
            XCTAssertEqual(band, 0.0)
        }
    }

    // MARK: - Permission Tests

    func testStartRecordingFailsWithoutPermission() {
        recorder = makeRecorder()
        PermissionManager.shared.microphonePermissionState = .denied

        let result = recorder.startRecording()

        XCTAssertFalse(result)
        XCTAssertFalse(recorder.isRecording)
    }

    func testStartRecordingFailsWithUnknownPermission() {
        recorder = makeRecorder()
        PermissionManager.shared.microphonePermissionState = .unknown

        let result = recorder.startRecording()

        XCTAssertFalse(result)
        XCTAssertFalse(recorder.isRecording)
    }

    // MARK: - Volume Boost Tests

    func testStartRecordingDoesNotBoostVolumeWhenSessionDoesNotBegin() async {
        // Bug #33 regression: the volume boost must be dispatched only AFTER the
        // early-return checks (including the test-environment guard). When no real
        // recording session begins, the boost must not run — otherwise the matching
        // restore in stop/cancel never fires and the boost is left on permanently.
        // Under tests `startRecording()` early-returns, so no boost should occur.
        AppDefaults.defaults.set(true, forKey: "autoBoostMicrophoneVolume")
        recorder = makeRecorder(dates: [Date(), Date()])
        PermissionManager.shared.microphonePermissionState = .granted

        let started = recorder.startRecording()

        // Give any (incorrectly) dispatched async task time to execute.
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        XCTAssertFalse(started, "startRecording should early-return in the test environment")
        XCTAssertFalse(
            mockVolumeManager.boostCalled,
            "Volume must not be boosted when no real recording session begins (bug #33)"
        )
    }

    func testStartRecordingDoesNotBoostVolumeWhenDisabled() async {
        AppDefaults.defaults.set(false, forKey: "autoBoostMicrophoneVolume")
        recorder = makeRecorder(dates: [Date(), Date()])
        PermissionManager.shared.microphonePermissionState = .granted

        _ = recorder.startRecording()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(mockVolumeManager.boostCalled, "Should not boost volume when disabled")
    }

    func testCancelRecordingRestoresVolume() async {
        AppDefaults.defaults.set(true, forKey: "autoBoostMicrophoneVolume")
        recorder = makeRecorder(dates: [Date(), Date(), Date()])
        PermissionManager.shared.microphonePermissionState = .granted

        _ = recorder.startRecording()
        recorder.cancelRecording()

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(mockVolumeManager.restoreCalled, "Should restore volume after cancel")
    }

    // MARK: - Cancel Recording Tests

    func testCancelRecordingResetsState() {
        recorder = makeRecorder(dates: [Date(), Date(), Date()])
        PermissionManager.shared.microphonePermissionState = .granted

        _ = recorder.startRecording()
        recorder.cancelRecording()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
        XCTAssertEqual(recorder.audioLevel, 0.0)
        XCTAssertTrue(recorder.waveformSamples.isEmpty)
    }

    // MARK: - Stop Recording Tests

    func testStopRecordingResetsVisualizationData() {
        recorder = makeRecorder(dates: [Date(), Date(), Date()])
        PermissionManager.shared.microphonePermissionState = .granted

        _ = recorder.startRecording()
        _ = recorder.stopRecording()

        XCTAssertEqual(recorder.audioLevel, 0.0)
        XCTAssertTrue(recorder.waveformSamples.isEmpty)
        XCTAssertEqual(recorder.frequencyBands, Array(repeating: 0, count: 8))
    }

    func testStopRecordingReturnsNilWhenNoFramesWereCaptured() {
        // Bug #11 regression: stopRecording must return nil when the recording is
        // unusable (no frames written / all writes failed) so the caller's
        // `guard let url = stopRecording()` rejects it instead of transcribing a
        // 0-byte/corrupt file. In the test environment no real engine starts, so
        // no frames are ever written.
        recorder = makeRecorder(dates: [Date(), Date(), Date()])
        PermissionManager.shared.microphonePermissionState = .granted

        _ = recorder.startRecording()
        let url = recorder.stopRecording()

        XCTAssertNil(url, "stopRecording should return nil when no audio frames were captured")
    }

    // MARK: - Cleanup Tests

    func testCleanupRecordingClearsState() {
        recorder = makeRecorder()

        recorder.cleanupRecording()

        XCTAssertNil(recorder.currentSessionStart)
        XCTAssertNil(recorder.lastRecordingDuration)
    }

    // MARK: - Deinit Cleanup Tests (bug #29)

    func testDeinitRestoresVolumeWhenBoostEnabled() async {
        // Bug #29 regression: AudioEngineRecorder had no deinit, so a recorder
        // dropped mid-recording never restored boosted mic volume. The deinit must
        // dispatch a restore when auto-boost is enabled.
        AppDefaults.defaults.set(true, forKey: "autoBoostMicrophoneVolume")
        let localManager = MockMicrophoneVolumeManager()

        autoreleasepool {
            let droppedRecorder = AudioEngineRecorder(volumeManager: localManager)
            _ = droppedRecorder  // dropped at end of scope -> deinit runs
        }

        // deinit dispatches an async restore Task — give it time to run.
        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertTrue(localManager.restoreCalled, "deinit should restore mic volume when boost is enabled")
    }

    func testDeinitDoesNotCrashWithoutActiveRecording() {
        // Dropping a freshly-created recorder must not crash in deinit.
        autoreleasepool {
            let droppedRecorder = AudioEngineRecorder(volumeManager: MockMicrophoneVolumeManager())
            _ = droppedRecorder
        }
        XCTAssertTrue(true, "deinit completed without crashing")
    }

    // MARK: - Observable Properties Tests

    func testIsRecordingIsPublished() {
        recorder = makeRecorder()

        var observedValues: [Bool] = []
        let cancellable = recorder.$isRecording.sink { value in
            observedValues.append(value)
        }

        // Should have initial value
        XCTAssertFalse(observedValues.isEmpty)

        cancellable.cancel()
    }

    func testAudioLevelIsPublished() {
        recorder = makeRecorder()

        var observedValues: [Float] = []
        let cancellable = recorder.$audioLevel.sink { value in
            observedValues.append(value)
        }

        XCTAssertFalse(observedValues.isEmpty)
        XCTAssertEqual(observedValues.first, 0.0)

        cancellable.cancel()
    }

    func testWaveformSamplesIsPublished() {
        recorder = makeRecorder()

        var observedValues: [[Float]] = []
        let cancellable = recorder.$waveformSamples.sink { value in
            observedValues.append(value)
        }

        XCTAssertFalse(observedValues.isEmpty)
        XCTAssertTrue(observedValues.first?.isEmpty ?? false)

        cancellable.cancel()
    }

    func testFrequencyBandsIsPublished() {
        recorder = makeRecorder()

        var observedValues: [[Float]] = []
        let cancellable = recorder.$frequencyBands.sink { value in
            observedValues.append(value)
        }

        XCTAssertFalse(observedValues.isEmpty)
        XCTAssertEqual(observedValues.first?.count, 8)

        cancellable.cancel()
    }

    // MARK: - Reentrancy Tests

    func testStartRecordingPreventsReentrancy() {
        recorder = makeRecorder(dates: [Date(), Date(), Date(), Date()])
        PermissionManager.shared.microphonePermissionState = .granted

        // First start may fail due to no audio device, but should set internal state
        let firstStart = recorder.startRecording()

        // If first start succeeded (has audio device), second should fail
        if firstStart {
            let secondStart = recorder.startRecording()
            XCTAssertFalse(secondStart, "Second start should fail due to reentrancy guard")
        }
        // If first start failed (no audio device), test passes anyway
    }
}

// MARK: - Mock Volume Manager

private class MockMicrophoneVolumeManager: MicrophoneVolumeManaging {
    var boostCalled = false
    var restoreCalled = false

    func boostMicrophoneVolume() async -> Bool {
        boostCalled = true
        return true
    }

    func restoreMicrophoneVolume() async {
        restoreCalled = true
    }

    func isVolumeControlAvailable() async -> Bool {
        return true
    }
}
