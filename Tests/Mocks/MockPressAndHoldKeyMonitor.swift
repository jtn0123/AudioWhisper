import Foundation
import AppKit
@testable import AudioWhisper

/// Mock PressAndHoldKeyMonitor for testing hotkey monitoring
final class MockPressAndHoldKeyMonitor {
    // MARK: - Configuration

    let configuration: PressAndHoldConfiguration
    private let keyDownHandler: () -> Void
    private let keyUpHandler: (() -> Void)?

    // MARK: - State

    private(set) var isStarted = false
    private(set) var isPressed = false

    // MARK: - Call Tracking

    var startCalled = false
    var startCallCount = 0
    var stopCalled = false
    var stopCallCount = 0

    // MARK: - Initialization

    init(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void,
        keyUpHandler: (() -> Void)? = nil
    ) {
        self.configuration = configuration
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
    }

    // MARK: - Public Methods

    func start() {
        stop()  // Match real implementation behavior
        startCalled = true
        startCallCount += 1
        isStarted = true
    }

    func stop() {
        stopCalled = true
        stopCallCount += 1
        isStarted = false
        isPressed = false
    }

    // MARK: - Test Simulation Methods

    /// Simulate a key down event
    func simulateKeyDown() {
        guard isStarted, !isPressed else { return }
        isPressed = true
        keyDownHandler()
    }

    /// Simulate a key up event
    func simulateKeyUp() {
        guard isStarted, isPressed else { return }
        isPressed = false
        keyUpHandler?()
    }

    /// Simulate a complete press and release cycle
    func simulatePressAndRelease() {
        simulateKeyDown()
        simulateKeyUp()
    }

    /// Simulate a modifier event (like flagsChanged)
    func simulateModifierEvent(keyDown: Bool) {
        if keyDown {
            simulateKeyDown()
        } else {
            simulateKeyUp()
        }
    }

    // MARK: - Test Helpers

    func reset() {
        isStarted = false
        isPressed = false
        startCalled = false
        startCallCount = 0
        stopCalled = false
        stopCallCount = 0
    }
}
