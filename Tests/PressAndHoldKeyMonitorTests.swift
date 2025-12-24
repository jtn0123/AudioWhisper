import XCTest
import AppKit
@testable import AudioWhisper

final class PressAndHoldKeyMonitorTests: XCTestCase {
    private var addedEvents: [(NSEvent.EventTypeMask, (NSEvent) -> Void)] = []
    private var removedEvents: [Any] = []

    override func tearDown() {
        addedEvents.removeAll()
        removedEvents.removeAll()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeMonitor(
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

    // MARK: - Thread Safety Tests (Bug #18 Regression Prevention)

    func testIsPressedThreadSafety() {
        // Bug #18 fix verification: Concurrent access to isPressed should not crash
        var keyDownCount = 0
        var keyUpCount = 0
        let lock = NSLock()

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {
                lock.lock()
                keyDownCount += 1
                lock.unlock()
            },
            keyUpHandler: {
                lock.lock()
                keyUpCount += 1
                lock.unlock()
            }
        )

        // Simulate concurrent transitions to detect race conditions
        let group = DispatchGroup()
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                monitor.processTransition(isKeyDownEvent: i % 2 == 0)
                group.leave()
            }
        }

        group.wait()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        // Main assertion: no crash occurred
        XCTAssertTrue(true, "Concurrent access should not crash (Bug #18 fix)")
    }

    func testRapidKeyPresses() {
        var downCount = 0
        var upCount = 0
        let lock = NSLock()

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {
                lock.lock()
                downCount += 1
                lock.unlock()
            },
            keyUpHandler: {
                lock.lock()
                upCount += 1
                lock.unlock()
            }
        )

        // Simulate rapid down-up-down-up sequence
        for _ in 0..<10 {
            monitor.processTransition(isKeyDownEvent: true)
            monitor.processTransition(isKeyDownEvent: false)
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))

        lock.lock()
        XCTAssertEqual(downCount, 10, "Should handle 10 rapid key downs")
        XCTAssertEqual(upCount, 10, "Should handle 10 rapid key ups")
        lock.unlock()
    }

    func testKeyDownKeyUpSequence() {
        let expectation = XCTestExpectation(description: "Both handlers called")
        expectation.expectedFulfillmentCount = 2

        var callOrder: [String] = []
        let lock = NSLock()

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {
                lock.lock()
                callOrder.append("down")
                lock.unlock()
                expectation.fulfill()
            },
            keyUpHandler: {
                lock.lock()
                callOrder.append("up")
                lock.unlock()
                expectation.fulfill()
            }
        )

        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)

        wait(for: [expectation], timeout: 1.0)

        lock.lock()
        XCTAssertEqual(callOrder, ["down", "up"])
        lock.unlock()
    }

    func testDoubleKeyDownIgnored() {
        var keyDownCount = 0
        let lock = NSLock()

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {
                lock.lock()
                keyDownCount += 1
                lock.unlock()
            },
            keyUpHandler: nil
        )

        // Three consecutive key downs - only first should count
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: true)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        lock.lock()
        XCTAssertEqual(keyDownCount, 1, "Duplicate key downs should be ignored")
        lock.unlock()
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

    func testDifferentKeyConfigurations() {
        let keys: [PressAndHoldKey] = [.rightCommand, .leftCommand, .rightOption, .leftOption, .rightControl, .leftControl, .globe]

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
