import CoreAudio
import XCTest
@testable import AudioWhisper

/// Fake output devices by UID. Removing a UID models the device disconnecting.
private final class FakeOutputs: AudioOutputVolumeControlling {
    var devices: [String: AudioDeviceID] = ["speakers": 1]
    var volumes: [AudioDeviceID: Float32] = [1: 0.5]
    var defaultDevice: AudioDeviceID? = 1
    var settable = true
    /// Rounds every write to this step, as coarse hardware does.
    var step: Float32?
    private(set) var writes: [Float32] = []

    func defaultOutputDevice() -> AudioDeviceID? { defaultDevice }
    func uid(of device: AudioDeviceID) -> String? { devices.first { $0.value == device }?.key }
    func device(withUID uid: String) -> AudioDeviceID? { devices[uid] }
    func volume(of device: AudioDeviceID) -> Float32? {
        devices.values.contains(device) ? volumes[device] : nil
    }

    func setVolume(_ volume: Float32, of device: AudioDeviceID) -> Bool {
        guard settable, devices.values.contains(device) else { return false }
        writes.append(volume)
        volumes[device] = step.map { $0 * (volume / $0).rounded() } ?? volume
        return true
    }
}

@MainActor
final class OutputDuckerTests: IsolatedXCTestCase {
    private var outputs: FakeOutputs!
    private var ducker: OutputDucker!

    override func setUp() {
        super.setUp()
        clearSettings()
        outputs = FakeOutputs()
        ducker = OutputDucker(controller: outputs)
    }

    override func tearDown() {
        clearSettings()
        super.tearDown()
    }

    func testOtherAudioIsLoweredAndPutBack() {
        ducker.duck()
        XCTAssertEqual(outputs.volumes[1]!, 0.15, accuracy: 0.0001)
        ducker.restore()
        XCTAssertEqual(outputs.volumes[1], 0.5)
        XCTAssertEqual(AppDefaults.loweredOutputVolumes, [:])
    }

    func testANewLaunchPutsBackWhatACrashLeftLowered() {
        ducker.duck()
        XCTAssertEqual(AppDefaults.loweredOutputVolumes["speakers"]?.original, 0.5)

        OutputDucker(controller: outputs).restore()
        XCTAssertEqual(outputs.volumes[1], 0.5)
    }

    func testAVolumeTheUserChangedWhileRecordingIsKept() {
        ducker.duck()
        outputs.volumes[1] = 0.8
        ducker.restore()
        XCTAssertEqual(outputs.volumes[1], 0.8)
        XCTAssertEqual(AppDefaults.loweredOutputVolumes, [:], "their choice is final, not retried")
    }

    func testCoarseHardwareStepsStillCountAsUntouched() {
        outputs.step = 1.0 / 16
        ducker.duck()
        XCTAssertEqual(outputs.volumes[1], 0.125, "0.15 lands on the nearest step")
        ducker.restore()
        XCTAssertEqual(outputs.volumes[1], 0.5)
    }

    func testADeviceThatDisconnectedIsPutBackWhenItReturns() {
        ducker.duck()
        outputs.devices["speakers"] = nil
        ducker.restore()
        XCTAssertNotNil(AppDefaults.loweredOutputVolumes["speakers"], "kept for later")

        outputs.devices["speakers"] = 1
        ducker.restore()
        XCTAssertEqual(outputs.volumes[1], 0.5)
    }

    func testAnotherDeviceCanBeLoweredWhileOneIsAway() {
        ducker.duck()
        outputs.devices = ["headphones": 2]
        outputs.volumes[2] = 0.6
        outputs.defaultDevice = 2
        ducker.duck()
        XCTAssertEqual(outputs.volumes[2]!, 0.18, accuracy: 0.0001)

        ducker.restore()
        outputs.devices["speakers"] = 1
        ducker.restore()
        XCTAssertEqual(outputs.volumes, [1: 0.5, 2: 0.6])
    }

    func testLoweringTwiceKeepsTheFirstOriginal() {
        ducker.duck()
        ducker.duck()
        ducker.restore()
        XCTAssertEqual(outputs.volumes[1], 0.5)
    }

    func testSilentOutputIsLeftAlone() {
        outputs.volumes[1] = 0.01
        ducker.duck()
        XCTAssertEqual(outputs.writes, [])
        XCTAssertEqual(AppDefaults.loweredOutputVolumes, [:])
    }

    func testAVolumeThatCannotBeSetLeavesNoRecord() {
        outputs.settable = false
        ducker.duck()
        XCTAssertEqual(outputs.volumes[1], 0.5)
        XCTAssertEqual(AppDefaults.loweredOutputVolumes, [:])
    }

    func testNoOutputDeviceIsHarmless() {
        outputs.defaultDevice = nil
        ducker.duck()
        ducker.restore()
        XCTAssertEqual(outputs.writes, [])
    }

    func testAnUnreadableRecordCountsAsNothingLowered() {
        AppDefaults.defaults.set(Data("not json".utf8), forKey: AppDefaults.Key.loweredOutputVolumes.rawValue)
        XCTAssertEqual(AppDefaults.loweredOutputVolumes, [:])
    }

    // MARK: - Recorder

    func testTheRecorderOnlyLowersWhenAsked() {
        let recorder = AudioEngineRecorder(outputDucker: ducker)
        recorder.lowerOtherAudio()
        XCTAssertEqual(outputs.writes, [])

        AppDefaults.lowerOtherAudioWhileRecording = true
        recorder.lowerOtherAudio()
        XCTAssertEqual(outputs.volumes[1]!, 0.15, accuracy: 0.0001)
        _ = recorder.stopRecording()
        XCTAssertEqual(outputs.volumes[1], 0.5)
    }

    func testCancellingPutsOtherAudioBackEvenIfTheSettingWasTurnedOff() {
        AppDefaults.lowerOtherAudioWhileRecording = true
        let recorder = AudioEngineRecorder(outputDucker: ducker)
        recorder.lowerOtherAudio()
        AppDefaults.lowerOtherAudioWhileRecording = false
        recorder.cancelRecording()
        XCTAssertEqual(outputs.volumes[1], 0.5)
    }

    func testADroppedRecorderPutsOtherAudioBack() async throws {
        AppDefaults.lowerOtherAudioWhileRecording = true
        var recorder: AudioEngineRecorder? = AudioEngineRecorder(outputDucker: ducker)
        recorder?.lowerOtherAudio()
        recorder = nil
        for _ in 0..<100 where outputs.volumes[1] != 0.5 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(outputs.volumes[1], 0.5)
    }

    private func clearSettings() {
        AppDefaults.removeValue(for: .lowerOtherAudioWhileRecording)
        AppDefaults.removeValue(for: .loweredOutputVolumes)
    }
}

/// The real binding, kept read-only: nothing here changes the Mac's volume.
final class CoreAudioOutputVolumeControllerTests: XCTestCase {
    private let controller = CoreAudioOutputVolumeController()
    private let missingDevice = AudioDeviceID(kAudioObjectUnknown)

    func testAMissingDeviceHasNoUIDOrVolume() {
        XCTAssertNil(controller.uid(of: missingDevice))
        XCTAssertNil(controller.volume(of: missingDevice))
        XCTAssertFalse(controller.setVolume(0.5, of: missingDevice))
    }

    func testAnUnknownUIDFindsNoDevice() {
        XCTAssertNil(controller.device(withUID: "audiowhisper.tests.\(UUID().uuidString)"))
    }

    func testTheDefaultOutputIsFoundAgainByItsUID() throws {
        // CI runners may have no output device; there is nothing to look up then.
        guard let device = controller.defaultOutputDevice() else { return }
        let uid = try XCTUnwrap(controller.uid(of: device))
        XCTAssertEqual(controller.device(withUID: uid), device)
        if let volume = controller.volume(of: device) { XCTAssertTrue((0...1).contains(volume)) }
    }
}
