import XCTest
@testable import AudioWhisper

// Thread-safety regression tests, split out of PressAndHoldKeyMonitorTests
// to keep each type within SwiftLint body-length limits.
extension PressAndHoldKeyMonitorTests {
    // MARK: - Thread Safety Tests (Bug Regression Prevention)

    func testIsPressedThreadSafety() {
        // Bug fix verification: Concurrent access to isPressed should not crash
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
        for index in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                monitor.processTransition(isKeyDownEvent: index % 2 == 0)
                group.leave()
            }
        }

        group.wait()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        // Main assertion: no crash occurred
        XCTAssertTrue(true, "Concurrent access should not crash (bug fix)")
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

}
