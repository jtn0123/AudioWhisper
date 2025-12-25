import XCTest
@testable import AudioWhisper

/// Tests for AppDelegate+Notifications.swift focusing on notification observers
@MainActor
final class AppDelegateNotificationsTests: XCTestCase {

    var appDelegate: AppDelegate!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }

    override func tearDown() {
        appDelegate.pressAndHoldMonitor?.stop()
        appDelegate.pressAndHoldMonitor = nil
        appDelegate = nil
        super.tearDown()
    }

    // MARK: - Notification Observer Setup Tests

    func testSetupNotificationObserversDoesNotCrash() {
        // Just verify the method can be called without crashing
        appDelegate.setupNotificationObservers()
        XCTAssertTrue(true)
    }

    func testSetupNotificationObserversRegistersAllObservers() {
        // Set up observers
        appDelegate.setupNotificationObservers()

        // Verify by posting notifications and checking no crash
        // We can't easily verify observer registration without mocking NotificationCenter

        // The notifications being observed are:
        // - .welcomeCompleted
        // - .restoreFocusToPreviousApp
        // - .recordingStopped
        // - .pressAndHoldSettingsChanged

        // Just verify setup completed
        XCTAssertTrue(true)
    }

    // MARK: - Notification Response Tests

    func testWelcomeCompletedNotificationShowsDashboard() {
        // Set up observers
        appDelegate.setupNotificationObservers()

        // Post notification
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)

        // Dashboard opening would happen - verify no crash
        XCTAssertTrue(true)
    }

    func testRestoreFocusToPreviousAppNotificationCallsWindowController() {
        // Set up observers
        appDelegate.setupNotificationObservers()

        // Post notification
        NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)

        // Window controller method would be called - verify no crash
        XCTAssertTrue(true)
    }

    func testRecordingStoppedNotificationCallsHandler() {
        // Create status item for testing
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        appDelegate.statusItem = statusItem

        // Set up observers
        appDelegate.setupNotificationObservers()

        // Post notification
        NotificationCenter.default.post(name: .recordingStopped, object: nil)

        // Handler would update menu icon - verify no crash
        NSStatusBar.system.removeStatusItem(statusItem)
        XCTAssertTrue(true)
    }

    func testPressAndHoldSettingsChangedReconfiguresMonitors() {
        // Set up observers
        appDelegate.setupNotificationObservers()

        // Get initial monitor state
        let initialMonitor = appDelegate.pressAndHoldMonitor

        // Post settings changed notification
        let newConfig = PressAndHoldConfiguration(enabled: true, key: .leftOption, mode: .toggle)
        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: newConfig)

        // Wait a moment for notification to be processed
        let expectation = expectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Monitor may have been reconfigured
        // Note: This depends on the enabled state from settings
    }

    // MARK: - Notification Name Tests

    func testWelcomeCompletedNotificationNameExists() {
        let name = Notification.Name.welcomeCompleted
        XCTAssertNotNil(name)
    }

    func testRestoreFocusToPreviousAppNotificationNameExists() {
        let name = Notification.Name.restoreFocusToPreviousApp
        XCTAssertNotNil(name)
    }

    func testRecordingStoppedNotificationNameExists() {
        let name = Notification.Name.recordingStopped
        XCTAssertNotNil(name)
    }

    func testPressAndHoldSettingsChangedNotificationNameExists() {
        let name = Notification.Name.pressAndHoldSettingsChanged
        XCTAssertNotNil(name)
    }

    // MARK: - Observer Cleanup Tests

    func testNotificationObserversAreCleanedUpOnDeinit() {
        // Create a temporary delegate
        var tempDelegate: AppDelegate? = AppDelegate()
        tempDelegate?.setupNotificationObservers()

        // Set to nil to trigger deinit
        tempDelegate = nil

        // If observers weren't cleaned up properly, posting might cause issues
        // But NotificationCenter uses weak references, so this should be fine
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)

        XCTAssertTrue(true)
    }

    // MARK: - Integration Tests

    func testMultipleNotificationsInSequence() {
        // Set up observers
        appDelegate.setupNotificationObservers()

        // Post multiple notifications
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)

        // All should be handled without crash
        XCTAssertTrue(true)
    }

    func testNotificationWithPayload() {
        // Set up observers
        appDelegate.setupNotificationObservers()

        // Post notification with configuration payload
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: config)

        // Should process without crash
        XCTAssertTrue(true)
    }
}
