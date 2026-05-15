import XCTest
import AppKit
@testable import AudioWhisper

// Duplicate-event regression tests, split out of PressAndHoldKeyMonitorTests
// to keep each type within SwiftLint body-length limits.
extension PressAndHoldKeyMonitorTests {
    // MARK: - Duplicate Event Tests (Bug Fix Regression)

    func testDuplicateKeyDownEventsAreIdempotent() {
        // Bug fix: When macOS sends multiple flagsChanged events for the same key state,
        // only the first should trigger the handler. This tests the fix where we check
        // modifier flags from the event instead of toggling isPressed.
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

        // Simulate multiple "key down" events arriving (as can happen with macOS)
        // All should be treated as "key is down" - only first triggers handler
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: true)

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        lock.lock()
        XCTAssertEqual(keyDownCount, 1, "Multiple key-down events should only trigger handler once")
        lock.unlock()
    }

    func testDuplicateKeyUpEventsAreIdempotent() {
        // Bug fix: Multiple "key up" events should only trigger handler once
        var keyUpCount = 0
        let lock = NSLock()

        let monitor = makeMonitor(
            configuration: PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold),
            keyDownHandler: {},
            keyUpHandler: {
                lock.lock()
                keyUpCount += 1
                lock.unlock()
            }
        )

        // First press and release
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: false)
        monitor.processTransition(isKeyDownEvent: false)  // Duplicate up
        monitor.processTransition(isKeyDownEvent: false)  // Another duplicate

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        lock.lock()
        XCTAssertEqual(keyUpCount, 1, "Multiple key-up events should only trigger handler once")
        lock.unlock()
    }

    func testRapidDuplicateEventsDoNotCauseFlickering() {
        // Bug fix regression test: Rapid duplicate events should not cause
        // the "flickering" behavior where state toggles incorrectly
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

        // Simulate the bug scenario: press key, macOS sends multiple events
        monitor.processTransition(isKeyDownEvent: true)
        monitor.processTransition(isKeyDownEvent: true)  // Duplicate - should be ignored

        // User releases key, macOS sends multiple events
        monitor.processTransition(isKeyDownEvent: false)
        monitor.processTransition(isKeyDownEvent: false)  // Duplicate - should be ignored

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))

        lock.lock()
        XCTAssertEqual(downCount, 1, "Should have exactly one key down")
        XCTAssertEqual(upCount, 1, "Should have exactly one key up")
        lock.unlock()
    }

    func testConcurrentDuplicateEventsAreHandledCorrectly() {
        // Bug fix: Even with concurrent duplicate events from different threads,
        // state should remain consistent
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

        let group = DispatchGroup()

        // Simulate concurrent "key down" events (all should result in single handler call)
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                monitor.processTransition(isKeyDownEvent: true)
                group.leave()
            }
        }

        group.wait()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        lock.lock()
        XCTAssertEqual(downCount, 1, "Concurrent key-down events should only trigger once")
        lock.unlock()

        // Now simulate concurrent "key up" events
        for _ in 0..<10 {
            group.enter()
            DispatchQueue.global().async {
                monitor.processTransition(isKeyDownEvent: false)
                group.leave()
            }
        }

        group.wait()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))

        lock.lock()
        XCTAssertEqual(upCount, 1, "Concurrent key-up events should only trigger once")
        lock.unlock()
    }

}
