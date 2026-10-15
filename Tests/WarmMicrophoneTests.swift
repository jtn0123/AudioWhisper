import AppKit
import AVFAudio
import CoreAudio
import XCTest
@testable import AudioWhisper

/// A 0.1 s mono buffer at 48 kHz holding `value` in every frame.
private func buffer(_ value: Float = 0.2) throws -> AVAudioPCMBuffer {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800))
    buffer.frameLength = 4_800
    let samples = try XCTUnwrap(buffer.floatChannelData?[0])
    for index in 0..<4_800 { samples[index] = value }
    return buffer
}

private final class Clock {
    var now: TimeInterval = 100
}

final class AudioFeedTests: XCTestCase {
    func testThePreRollKeepsOnlyTheMomentBeforeTheShortcut() throws {
        let feed = AudioFeed()
        for _ in 0..<6 { feed.receive(try buffer()) }
        XCTAssertEqual(feed.preRollFrames, 14_400, "0.3 s at 48 kHz")
    }

    func testThePreRollArrivesBeforeTheFirstLiveBuffer() throws {
        let feed = AudioFeed()
        feed.receive(try buffer(0.1))
        feed.receive(try buffer(0.2))
        var heard: [Float] = []
        feed.attach { heard.append($0.floatChannelData![0][0]) }
        feed.receive(try buffer(0.3))
        XCTAssertEqual(heard, [0.1, 0.2, 0.3])
        XCTAssertEqual(feed.preRollFrames, 0)
    }

    func testNothingReachesARecordingAfterDetach() throws {
        let feed = AudioFeed()
        var heard = 0
        feed.attach { _ in heard += 1 }
        feed.receive(try buffer())
        feed.detach()
        feed.receive(try buffer())
        XCTAssertEqual(heard, 1)
        XCTAssertEqual(feed.preRollFrames, 4_800, "back to collecting pre-roll")
    }

    func testThePreRollIsACopyNotTheEnginesBuffer() throws {
        let feed = AudioFeed()
        let original = try buffer(0.1)
        feed.receive(original)
        original.floatChannelData![0][0] = 0.9
        var first: Float?
        feed.attach { first = $0.floatChannelData![0][0] }
        XCTAssertEqual(first, 0.1)
    }

    func testFlowIsMeasuredFromTheLastDelivery() throws {
        let clock = Clock()
        let feed = AudioFeed(clock: { clock.now })
        XCTAssertFalse(feed.isFlowing(within: 0.5), "nothing has arrived yet")
        feed.receive(try buffer())
        clock.now += 0.4
        XCTAssertTrue(feed.isFlowing(within: 0.5))
        clock.now += 0.2
        XCTAssertFalse(feed.isFlowing(within: 0.5))
    }
}

@MainActor
private final class FakeMicrophones {
    final class Input {
        let uid: String
        var running = false
        var stopped = false
        init(uid: String) { self.uid = uid }
    }

    var opened: [Input] = []
    var feeds: [AudioFeed] = []
    var bluetooth: Set<String> = []
    var failOpen = false
    var failStart = false
    var slowOpen = false
    var pendingOpen: CheckedContinuation<Void, Never>?

    var hardware: WarmMicrophone<Input>.Hardware {
        .init(
            open: { uid in
                if self.slowOpen { await withCheckedContinuation { self.pendingOpen = $0 } }
                if self.failOpen { throw AudioInputError.unavailable }
                let input = Input(uid: uid)
                self.opened.append(input)
                return input
            },
            start: { input, feed in
                if self.failStart { throw AudioInputError.invalidFormat }
                input.running = true
                self.feeds.append(feed)
            },
            stop: { input in
                input.running = false
                input.stopped = true
            },
            isCurrent: { input, _ in input.running },
            isBluetooth: { self.bluetooth.contains($0) })
    }
}

@MainActor
final class WarmMicrophoneTests: XCTestCase {
    private var fake: FakeMicrophones!
    private var clock: Clock!
    private var microphone: WarmMicrophone<FakeMicrophones.Input>!
    private var enabled = true
    private var chosen = "usb"
    private var recording = false

    override func setUp() async throws {
        try await super.setUp()
        fake = FakeMicrophones()
        clock = Clock()
        let clock = clock!
        microphone = WarmMicrophone(hardware: fake.hardware, makeFeed: { AudioFeed(clock: { clock.now }) })
        microphone.isEnabled = { [unowned self] in self.enabled }
        microphone.isAllowed = { true }
        microphone.chosenUID = { [unowned self] in self.chosen }
        microphone.recordingActive = { [unowned self] in self.recording }
    }

    private func warmUp() async throws -> FakeMicrophones.Input {
        await microphone.refresh()?.value
        XCTAssertTrue(microphone.isWarm)
        let feed = try XCTUnwrap(fake.feeds.last)
        feed.receive(try buffer())
        return try XCTUnwrap(fake.opened.last)
    }

    func testNothingOpensUnlessEnabledAndAllowed() async {
        enabled = false
        XCTAssertNil(microphone.refresh())
        enabled = true
        microphone.isAllowed = { false }
        XCTAssertNil(microphone.refresh())
        XCTAssertTrue(fake.opened.isEmpty)
    }

    func testTheChosenMicrophoneIsOpenedAndStarted() async throws {
        let input = try await warmUp()
        XCTAssertEqual(input.uid, "usb")
        XCTAssertTrue(input.running)
    }

    func testABluetoothHeadsetIsNeverHeldOpen() {
        fake.bluetooth = ["usb"]
        XCTAssertNil(microphone.refresh())
        XCTAssertTrue(fake.opened.isEmpty)
    }

    func testTheHeldInputIsLentToARecordingFromTheSameMicrophone() async throws {
        let input = try await warmUp()
        clock.now += 0.2
        let lent = try XCTUnwrap(microphone.lend(for: "usb"))
        XCTAssertTrue(lent.input === input)
        XCTAssertFalse(microphone.isWarm)
        XCTAssertNil(microphone.refresh(), "a lent input is not opened twice")
    }

    func testARecordingFromAnotherMicrophoneReleasesTheHeldOne() async throws {
        let input = try await warmUp()
        XCTAssertNil(microphone.lend(for: "headset"))
        XCTAssertTrue(input.stopped)
        guard case .cold = microphone.state else { return XCTFail("expected cold, got \(microphone.state)") }
    }

    func testAnInputThatWentQuietIsNotTrusted() async throws {
        let input = try await warmUp()
        clock.now += 1
        XCTAssertNil(microphone.lend(for: "usb"))
        XCTAssertTrue(input.stopped)
    }

    func testAnInputThatStoppedIsNotTrusted() async throws {
        let input = try await warmUp()
        input.running = false
        XCTAssertNil(microphone.lend(for: "usb"))
    }

    func testARecordingThatStartsWhileOpeningWins() async throws {
        fake.slowOpen = true
        let opening = microphone.refresh()
        try await waitUntil { self.fake.pendingOpen != nil }
        recording = true
        fake.pendingOpen?.resume()
        await opening?.value
        XCTAssertFalse(microphone.isWarm)
        XCTAssertTrue(fake.feeds.isEmpty, "never started")
        XCTAssertEqual(fake.opened.last?.stopped, true, "and not left open")
    }

    func testLendingWhileOpeningCancelsTheOpen() async throws {
        fake.slowOpen = true
        let opening = microphone.refresh()
        try await waitUntil { self.fake.pendingOpen != nil }
        XCTAssertNil(microphone.lend(for: "usb"))
        fake.pendingOpen?.resume()
        await opening?.value
        XCTAssertFalse(microphone.isWarm)
        XCTAssertTrue(fake.feeds.isEmpty)
    }

    func testAReclaimedInputIsReadyForTheNextRecording() async throws {
        _ = try await warmUp()
        let lent = try XCTUnwrap(microphone.lend(for: "usb"))
        var heard = 0
        lent.feed.attach { _ in heard += 1 }
        XCTAssertEqual(heard, 1, "the pre-roll")
        microphone.reclaim(lent)
        lent.feed.receive(try buffer())
        XCTAssertEqual(heard, 1, "the recording no longer hears it")
        XCTAssertTrue(microphone.isWarm)
        XCTAssertNotNil(microphone.lend(for: "usb"))
    }

    func testTurningTheSettingOffDuringARecordingReleasesItAfterwards() async throws {
        let input = try await warmUp()
        let lent = try XCTUnwrap(microphone.lend(for: "usb"))
        enabled = false
        microphone.coolDown()
        XCTAssertFalse(input.stopped, "the recording keeps its microphone")
        microphone.reclaim(lent)
        XCTAssertTrue(input.stopped)
        XCTAssertFalse(microphone.isWarm)
    }

    func testAnInputThatStoppedDuringTheRecordingIsReplaced() async throws {
        let first = try await warmUp()
        let lent = try XCTUnwrap(microphone.lend(for: "usb"))
        first.running = false
        microphone.reclaim(lent)
        try await waitUntil { self.microphone.isWarm }
        XCTAssertEqual(fake.opened.count, 2)
    }

    func testTurningTheSettingOffReleasesTheMicrophone() async throws {
        let input = try await warmUp()
        enabled = false
        microphone.refresh()
        XCTAssertTrue(input.stopped)
        XCTAssertFalse(microphone.isWarm)
    }

    func testADefaultInputChangeReopens() async throws {
        let first = try await warmUp()
        microphone.invalidate()
        try await waitUntil { self.microphone.isWarm }
        XCTAssertTrue(first.stopped)
        XCTAssertEqual(fake.opened.count, 2)
    }

    func testFailuresLeaveTheMicrophoneClosed() async {
        fake.failOpen = true
        await microphone.refresh()?.value
        XCTAssertFalse(microphone.isWarm)

        fake.failOpen = false
        fake.failStart = true
        await microphone.refresh()?.value
        XCTAssertFalse(microphone.isWarm)
        XCTAssertEqual(fake.opened.last?.stopped, true)
    }

    func testReclaimingAnInputThatWasNotLentStopsIt() async throws {
        _ = try await warmUp()
        let stranger = WarmMicrophone<FakeMicrophones.Input>.Held(
            input: .init(uid: "other"), uid: "other", feed: AudioFeed())
        microphone.reclaim(stranger)
        XCTAssertTrue(stranger.input.stopped)
        XCTAssertTrue(microphone.isWarm, "the held input is untouched")
    }

    func testTurningTheSettingOffWhileOpeningDropsTheInput() async throws {
        fake.slowOpen = true
        let opening = microphone.refresh()
        try await waitUntil { self.fake.pendingOpen != nil }
        enabled = false
        XCTAssertNil(microphone.refresh())
        fake.pendingOpen?.resume()
        await opening?.value
        XCTAssertFalse(microphone.isWarm)
        XCTAssertTrue(fake.feeds.isEmpty, "never started")
        XCTAssertEqual(fake.opened.last?.stopped, true)
    }

    func testSleepReleasesTheMicrophoneAndWakeOpensItAgain() async throws {
        let workspace = NotificationCenter()
        let watchers = microphone.watchSystem(on: workspace, wakeDelay: .zero)
        XCTAssertEqual(watchers.count, 3, "sleep, wake and the default input")
        let first = try await warmUp()

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await waitUntil { !self.microphone.isWarm }
        XCTAssertTrue(first.stopped)

        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await waitUntil { self.microphone.isWarm }
        XCTAssertEqual(fake.opened.count, 2)
    }

    func testReleasedWatchersNoLongerFollowSleep() async throws {
        let workspace = NotificationCenter()
        var watchers: [AnyObject]? = microphone.watchSystem(on: workspace, wakeDelay: .zero)
        XCTAssertNotNil(watchers)
        watchers = nil
        let input = try await warmUp()

        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(input.stopped)
        XCTAssertTrue(microphone.isWarm)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}

final class AudioDeviceTransportTests: XCTestCase {
    func testOnlyBluetoothTransportsCountAsBluetooth() {
        XCTAssertTrue(AudioDeviceTransport.isBluetooth(transport: kAudioDeviceTransportTypeBluetooth))
        XCTAssertTrue(AudioDeviceTransport.isBluetooth(transport: kAudioDeviceTransportTypeBluetoothLE))
        XCTAssertFalse(AudioDeviceTransport.isBluetooth(transport: kAudioDeviceTransportTypeBuiltIn))
        XCTAssertFalse(AudioDeviceTransport.isBluetooth(transport: kAudioDeviceTransportTypeUSB))
    }

    func testADeviceThatCannotBeReadIsNotBluetooth() {
        XCTAssertFalse(AudioDeviceTransport.isBluetooth(AudioDeviceID(kAudioObjectUnknown)))
    }
}

/// The setting itself, and the guarantee that tests never open a real microphone.
final class KeepMicrophoneReadySettingTests: IsolatedXCTestCase {
    override func setUp() {
        super.setUp()
        AppDefaults.removeValue(for: .keepMicrophoneReady)
    }

    override func tearDown() {
        AppDefaults.removeValue(for: .keepMicrophoneReady)
        super.tearDown()
    }

    func testTheSettingIsOffUntilTurnedOn() {
        XCTAssertFalse(AppDefaults.keepMicrophoneReady)
        AppDefaults.keepMicrophoneReady = true
        XCTAssertTrue(AppDefaults.keepMicrophoneReady)
    }

    @MainActor
    func testTheRecorderWatchesTheSystemButNeverOpensAMicrophoneUnderTests() {
        AppDefaults.keepMicrophoneReady = true
        let recorder = AudioEngineRecorder()
        recorder.startWarmMicrophone()
        XCTAssertEqual(recorder.warmWatchers.count, 3, "sleep, wake and the default input")
        XCTAssertNil(recorder.warmMicrophone.refresh())
        XCTAssertFalse(recorder.warmMicrophone.isWarm)
    }
}

/// The recorder's side: a capture fed by a held input.
@MainActor
final class AudioEngineRecorderWarmTests: XCTestCase {
    func testTheMomentBeforeTheShortcutOpensTheRecording() throws {
        let feed = AudioFeed()
        for _ in 0..<2 { feed.receive(try buffer()) }
        let recorder = AudioEngineRecorder()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("warm-\(UUID()).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        try recorder.beginCaptureFile(at: url, format: format)
        recorder.attach(feed)
        feed.receive(try buffer())

        XCTAssertEqual(recorder.stopRecording(), url)
        XCTAssertEqual(recorder.lastRecordingSignal?.frames, 14_400, "two pre-roll buffers and one live one")
        feed.receive(try buffer())
        XCTAssertEqual(feed.preRollFrames, 4_800, "stopping hands the feed back")
    }

    func testTheEngineTapFeedsTheHeldInput() throws {
        let feed = AudioFeed()
        let tap = WarmMicrophone<PreparedAudioEngine>.tap(into: feed)
        tap(try buffer(), AVAudioTime(hostTime: 0))
        XCTAssertEqual(feed.preRollFrames, 4_800)
    }

    func testTheReadyMicrophoneFollowsTheRecordersChoiceAndState() {
        let recorder = AudioEngineRecorder(
            microphoneChooser: MicrophoneChooser(connected: { [] }, defaultUID: { nil }, lidClosed: { false }))
        XCTAssertEqual(recorder.warmMicrophone.chosenUID(), "")
        XCTAssertFalse(recorder.warmMicrophone.recordingActive())
        XCTAssertNil(recorder.lendWarmInput(), "nothing is held under tests")
    }
}

/// Following the system default input: the listener Core Audio calls, and its removal.
@MainActor
final class DefaultInputWatchTests: XCTestCase {
    func testReleasingTheWatchRemovesItsHandler() {
        let before = DefaultInputWatchers.shared.count
        var registration: Registration? = AudioDeviceTransport.watchDefaultInput {}
        XCTAssertNotNil(registration)
        XCTAssertEqual(DefaultInputWatchers.shared.count, before + 1)
        registration = nil
        XCTAssertEqual(DefaultInputWatchers.shared.count, before)
    }

    func testAChangeReachesTheHandlerOnTheMainActorUntilItIsRemoved() async throws {
        var calls = 0
        let id = DefaultInputWatchers.shared.add {
            XCTAssertTrue(Thread.isMainThread)
            calls += 1
        }
        notifyFromAnotherThread(id)
        try await waitUntil { calls == 1 }

        notifyFromAnotherThread(id)
        DefaultInputWatchers.shared.remove(id)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(calls, 1, "a change already in flight is dropped once the watch is gone")
    }

    /// Calls the listener the way Core Audio does: off the main thread.
    private func notifyFromAnotherThread(_ id: Int) {
        let token = UnsafeMutableRawPointer(bitPattern: id)
        DispatchQueue.global().sync {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            _ = AudioDeviceTransport.defaultInputChanged(AudioObjectID(kAudioObjectSystemObject), 1, &address, token)
        }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}
