import XCTest
import AppKit
@testable import AudioWhisper

final class PressAndHoldKeyMonitorTests: XCTestCase {
    var addedEvents: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = []
    var removedEvents: [Any] = []
    var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()
        testSuiteName = "com.audiowhisper.tests.pressandhold.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)!
    }

    override func tearDown() {
        addedEvents.removeAll()
        removedEvents.removeAll()
        if let suiteName = testSuiteName {
            testDefaults.removePersistentDomain(forName: suiteName)
        }
        testDefaults = nil
        testSuiteName = nil
        super.tearDown()
    }

    // MARK: - Helpers

    func makeMonitor(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void = {},
        keyUpHandler: (() -> Void)? = nil
    ) -> PressAndHoldKeyMonitor {
        let addMonitor: PressAndHoldKeyMonitor.EventMonitorFactory = { [weak self] mask, handler in
            self?.addedEvents.append((mask, handler))
            return self?.addedEvents.count ?? 0
        }

        let removeMonitor: PressAndHoldKeyMonitor.EventMonitorRemoval = { [weak self] token in
            self?.removedEvents.append(token)
        }

        return PressAndHoldKeyMonitor(
            configuration: configuration,
            keyDownHandler: keyDownHandler,
            keyUpHandler: keyUpHandler,
            addGlobalMonitor: addMonitor,
            removeMonitor: removeMonitor
        )
    }

    // MARK: - start()

    func testStartRegistersFlagMonitorForModifierKey() {
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        let monitor = makeMonitor(configuration: config)

        monitor.start()

        XCTAssertEqual(addedEvents.count, 1)
        XCTAssertEqual(addedEvents.first?.0, .flagsChanged)
    }

    // MARK: - Transitions

    func testKeyDownInvokesHandlerOnlyOnceUntilReleased() {
        let expectationDown = expectation(description: "keyDown")
        expectationDown.expectedFulfillmentCount = 2

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {
                expectationDown.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)  // first press
        monitor.processTransition(isKeyDownEvent: true)  // repeat press ignored
        monitor.processTransition(isKeyDownEvent: false) // release
        monitor.processTransition(isKeyDownEvent: true)  // second press

        wait(for: [expectationDown], timeout: 1.0)
    }

    func testKeyUpInvokesHandlerWhenConfigured() {
        let expectationUp = expectation(description: "keyUp")

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: {
                expectationUp.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)

        wait(for: [expectationUp], timeout: 1.0)
    }

    func testKeyUpHandlerNotCalledWhenNeverPressed() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: {
                XCTFail("Key up should not fire without prior key down")
            }
        )

        monitor.processTransition(isKeyDownEvent: false)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }

    // MARK: - stop()

    func testStopRemovesRegisteredMonitors() {
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        )

        monitor.start()
        monitor.stop()

        XCTAssertEqual(removedEvents.count, 1)
    }

    // MARK: - Start/Stop Lifecycle Tests

    func testStartStopStartSequence() {
        var startCount = 0
        var stopCount = 0

        let monitor = PressAndHoldKeyMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: nil,
            addGlobalMonitor: { _, _ in
                startCount += 1
                return "mock" as Any
            },
            removeMonitor: { _ in stopCount += 1 }
        )

        monitor.start()
        monitor.stop()
        monitor.start()

        XCTAssertEqual(startCount, 2, "Should be able to restart after stop")
        XCTAssertEqual(stopCount, 1, "Stop should have been called once")
    }

    func testStopResetsIsPressedState() {
        var keyDownCalled = false

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: { keyDownCalled = true },
            keyUpHandler: nil
        )

        // Simulate key press
        monitor.processTransition(isKeyDownEvent: true)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        keyDownCalled = false

        // Stop should reset state
        monitor.stop()

        // After stop and restart, a new key down should work
        monitor.start()
        monitor.processTransition(isKeyDownEvent: true)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertTrue(keyDownCalled, "Key down should work after stop/start")
    }

    // MARK: - Configuration Tests

    func testHoldModeHasKeyUpHandler() {
        var keyUpCalled = false

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: { keyUpCalled = true }
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertTrue(keyUpCalled, "Hold mode should call key up handler")
    }

    func testToggleModeNoKeyUpHandler() {
        // In toggle mode, keyUpHandler is typically nil
        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .toggle),
            keyDownHandler: {},
            keyUpHandler: nil
        )

        // Should not crash when key up occurs with nil handler
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)

        XCTAssertTrue(true, "Should handle nil keyUpHandler gracefully")
    }

    // MARK: - Left/Right Modifier Distinction (bug #3)

    func testIsKeyDownDistinguishesLeftAndRightCommand() {
        // Bug #3: the device-independent .command flag is identical for both
        // command keys. Using the device-dependent NX_DEVICE*CMDKEYMASK bits,
        // left vs. right must be told apart.
        let leftCmdMask = NSEvent.ModifierFlags(rawValue: 0x00000008)  // NX_DEVICELCMDKEYMASK
        let rightCmdMask = NSEvent.ModifierFlags(rawValue: 0x00000010) // NX_DEVICERCMDKEYMASK

        XCTAssertTrue(PressAndHoldKey.leftCommand.isKeyDown(in: leftCmdMask))
        XCTAssertFalse(PressAndHoldKey.leftCommand.isKeyDown(in: rightCmdMask))

        XCTAssertTrue(PressAndHoldKey.rightCommand.isKeyDown(in: rightCmdMask))
        XCTAssertFalse(PressAndHoldKey.rightCommand.isKeyDown(in: leftCmdMask))
    }

    func testRightCommandReleaseNotMaskedByHeldLeftCommand() {
        // Core bug #3 scenario: user holds Left-Command while their configured key
        // is Right-Command. Releasing Right-Command (only Left-Command still down)
        // must report the configured Right-Command as NOT down.
        let onlyLeftCmd = NSEvent.ModifierFlags(rawValue: 0x00000008)
        XCTAssertFalse(
            PressAndHoldKey.rightCommand.isKeyDown(in: onlyLeftCmd),
            "Holding Left-Command must not keep Right-Command reported as down"
        )

        let bothCmd = NSEvent.ModifierFlags(rawValue: 0x00000008 | 0x00000010)
        XCTAssertTrue(PressAndHoldKey.rightCommand.isKeyDown(in: bothCmd))
        XCTAssertTrue(PressAndHoldKey.leftCommand.isKeyDown(in: bothCmd))
    }

    func testIsKeyDownDistinguishesLeftAndRightOptionAndControl() {
        let leftOpt = NSEvent.ModifierFlags(rawValue: 0x00000020)
        let rightOpt = NSEvent.ModifierFlags(rawValue: 0x00000040)
        XCTAssertTrue(PressAndHoldKey.leftOption.isKeyDown(in: leftOpt))
        XCTAssertFalse(PressAndHoldKey.leftOption.isKeyDown(in: rightOpt))
        XCTAssertTrue(PressAndHoldKey.rightOption.isKeyDown(in: rightOpt))

        let leftCtl = NSEvent.ModifierFlags(rawValue: 0x00000001)
        let rightCtl = NSEvent.ModifierFlags(rawValue: 0x00002000)
        XCTAssertTrue(PressAndHoldKey.leftControl.isKeyDown(in: leftCtl))
        XCTAssertFalse(PressAndHoldKey.leftControl.isKeyDown(in: rightCtl))
        XCTAssertTrue(PressAndHoldKey.rightControl.isKeyDown(in: rightCtl))
    }

    func testGlobeFallsBackToDeviceIndependentFlag() {
        // Globe/Fn has no left/right variant — falls back to the .function flag.
        XCTAssertNil(PressAndHoldKey.globe.deviceDependentMask)
        XCTAssertTrue(PressAndHoldKey.globe.isKeyDown(in: .function))
        XCTAssertFalse(PressAndHoldKey.globe.isKeyDown(in: .command))
    }

    // MARK: - Stuck-Key Watchdog (bug #4)

    func testWatchdogReleasesStuckKeyWhenPhysicalStateIsUp() {
        // Bug #4: if a key-up flagsChanged event is missed, isPressed stays true and
        // the next press is ignored. The watchdog reconciles against the real
        // physical modifier state and synthesizes the missed release.
        let flagsBox = ModifierFlagsBox(value: NSEvent.ModifierFlags(rawValue: 0x00000010))
        let keyUpExpectation = expectation(description: "watchdog synthesizes release")

        let monitor = PressAndHoldKeyMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: { keyUpExpectation.fulfill() },
            addGlobalMonitor: { _, _ in "mock" as Any },
            removeMonitor: { _ in },
            currentModifierFlags: { flagsBox.value }
        )

        monitor.start()
        monitor.processTransition(isKeyDownEvent: true)  // key down -> starts watchdog
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        // Simulate the missed key-up: the key is now physically released.
        flagsBox.value = NSEvent.ModifierFlags(rawValue: 0)

        // Watchdog interval is 0.25s — wait long enough for it to fire.
        wait(for: [keyUpExpectation], timeout: 2.0)
        monitor.stop()
    }

    func testWatchdogDoesNotReleaseWhileKeyStillHeld() {
        // The watchdog must NOT synthesize a release while the configured key is
        // genuinely still physically down.
        let flagsBox = ModifierFlagsBox(value: NSEvent.ModifierFlags(rawValue: 0x00000010))
        var keyUpCalled = false

        let monitor = PressAndHoldKeyMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: { keyUpCalled = true },
            addGlobalMonitor: { _, _ in "mock" as Any },
            removeMonitor: { _ in },
            currentModifierFlags: { flagsBox.value }
        )

        monitor.start()
        monitor.processTransition(isKeyDownEvent: true)

        // Let several watchdog cycles run while the key remains held.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.7))

        XCTAssertFalse(keyUpCalled, "Watchdog must not release a key that is still physically down")
        monitor.stop()
    }

    func testDifferentKeyConfigurations() {
        let keys: [PressAndHoldKey] = [
            .rightCommand, .leftCommand, .rightOption, .leftOption,
            .rightControl, .leftControl, .globe
        ]

        for key in keys {
            let monitor = makeMonitor(
                configuration: PressAndHoldConfiguration(enabled: true, key: key, mode: .hold),
                keyDownHandler: {},
                keyUpHandler: {}
            )

            // Should not crash for any key configuration
            XCTAssertNotNil(monitor, "Monitor should be created for \(key)")
        }
    }

}

/// Thread-safe holder for a `NSEvent.ModifierFlags` value, used to feed a mutable
/// physical-modifier-state into the monitor's injected `currentModifierFlags` closure
/// from tests. The closure can be invoked from the watchdog timer.
private final class ModifierFlagsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: NSEvent.ModifierFlags

    init(value: NSEvent.ModifierFlags) {
        self._value = value
    }

    var value: NSEvent.ModifierFlags {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}
