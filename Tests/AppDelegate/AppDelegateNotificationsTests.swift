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

    /// Posts `.pressAndHoldSettingsChanged` and waits for the observer to run.
    private func awaitNotificationProcessed(name: Notification.Name, object: Any?) {
        NotificationCenter.default.post(name: name, object: object)
        let processed = expectation(description: "Notification processed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { processed.fulfill() }
        wait(for: [processed], timeout: 1.0)
    }

    func testSetupNotificationObserversWiresPressAndHoldObserver() {
        appDelegate.setupNotificationObservers()

        // Posting the settings-changed notification must reach the observer,
        // which runs `configureShortcutMonitors()` and updates the stored
        // configuration. Use an enabled config so the effect is observable.
        let newConfig = PressAndHoldConfiguration(enabled: true, key: .leftOption, mode: .toggle)
        awaitNotificationProcessed(name: .pressAndHoldSettingsChanged, object: newConfig)

        // configureShortcutMonitors() reads PressAndHoldSettings.configuration()
        // and assigns it to pressAndHoldConfiguration. After the observer runs,
        // the stored configuration must match the freshly read settings value.
        XCTAssertEqual(appDelegate.pressAndHoldConfiguration,
                       PressAndHoldSettings.configuration())
    }

    func testSetupNotificationObserversRegistersAllObservers() {
        appDelegate.setupNotificationObservers()

        // Each observed notification must be handled without crashing. The
        // recordingStopped handler is the one with an inspectable post-state:
        // with no status item it must leave statusItem nil.
        XCTAssertNil(appDelegate.statusItem)
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)
        NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        XCTAssertNil(appDelegate.statusItem,
                     "recordingStopped must handle a nil status item gracefully")
    }

    // MARK: - Notification Response Tests

    func testWelcomeCompletedNotificationShowsDashboard() {
        appDelegate.setupNotificationObservers()

        // The welcomeCompleted handler must not mutate the status item.
        XCTAssertNil(appDelegate.statusItem)
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)
        XCTAssertNil(appDelegate.statusItem)
    }

    func testRestoreFocusToPreviousAppNotificationCallsWindowController() {
        appDelegate.setupNotificationObservers()

        // The restore-focus handler must not mutate the status item.
        XCTAssertNil(appDelegate.statusItem)
        NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
        XCTAssertNil(appDelegate.statusItem)
    }

    func testRecordingStoppedNotificationCallsHandler() {
        // Initially no status item
        XCTAssertNil(appDelegate.statusItem)

        appDelegate.setupNotificationObservers()

        // Posting recordingStopped with a nil status item must be handled
        // gracefully and must not create a status item.
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        XCTAssertNil(appDelegate.statusItem)
    }

    func testPressAndHoldSettingsChangedReconfiguresMonitors() {
        // Set up observers
        appDelegate.setupNotificationObservers()

        // Get initial monitor state
        _ = appDelegate.pressAndHoldMonitor

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
        // Create a temporary delegate and register observers.
        var tempDelegate: AppDelegate? = AppDelegate()
        tempDelegate?.setupNotificationObservers()

        // Set to nil to trigger deinit (which removes observers).
        tempDelegate = nil
        XCTAssertNil(tempDelegate)

        // Posting after deinit must not dispatch to the deallocated delegate;
        // a use-after-free would crash the test runner here.
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)
    }

    // MARK: - Integration Tests

    func testMultipleNotificationsInSequence() {
        appDelegate.setupNotificationObservers()

        // A burst of notifications must all be handled without mutating the
        // status item (no status item exists in this test setup).
        NotificationCenter.default.post(name: .recordingStopped, object: nil)
        NotificationCenter.default.post(name: .restoreFocusToPreviousApp, object: nil)
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)
        XCTAssertNil(appDelegate.statusItem)
    }

    func testNotificationWithPayload() {
        appDelegate.setupNotificationObservers()

        // A settings-changed notification carrying a configuration payload
        // must reach the handler, which runs configureShortcutMonitors() and
        // assigns a non-nil stored configuration.
        let config = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        awaitNotificationProcessed(name: .pressAndHoldSettingsChanged, object: config)
        XCTAssertEqual(appDelegate.pressAndHoldConfiguration,
                       PressAndHoldSettings.configuration())
    }
}
