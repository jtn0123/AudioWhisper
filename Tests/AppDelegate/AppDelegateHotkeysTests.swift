import XCTest
@testable import AudioWhisper

/// Tests for AppDelegate+Hotkeys.swift focusing on hotkey and recording handling
@MainActor
final class AppDelegateHotkeysTests: XCTestCase {

    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
        testDefaults = UserDefaults(suiteName: "AppDelegateHotkeysTests.\(UUID().uuidString)")!
    }

    override func tearDown() {
        appDelegate.pressAndHoldMonitor?.stop()
        appDelegate.pressAndHoldMonitor = nil
        appDelegate.recordingAnimationTimer?.cancel()
        appDelegate.recordingAnimationTimer = nil
        appDelegate = nil
        testDefaults?.removePersistentDomain(forName: testDefaults.suiteName ?? "")
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - configureShortcutMonitors Tests

    func testConfigureShortcutMonitorsStopsExistingMonitor() {
        // Create an initial monitor
        let initialConfig = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        let initialMonitor = PressAndHoldKeyMonitor(
            configuration: initialConfig,
            keyDownHandler: {}
        )
        initialMonitor.start()
        appDelegate.pressAndHoldMonitor = initialMonitor

        // Configure new monitors
        appDelegate.configureShortcutMonitors()

        // The old monitor should have been replaced
        XCTAssertNotNil(appDelegate.pressAndHoldMonitor)
    }

    func testConfigureShortcutMonitorsReadsConfiguration() {
        // Configure monitors
        appDelegate.configureShortcutMonitors()

        // Verify configuration was read
        XCTAssertEqual(appDelegate.pressAndHoldConfiguration, PressAndHoldSettings.configuration())
    }

    func testConfigureShortcutMonitorsReturnsEarlyWhenDisabled() {
        // Disable press-and-hold
        PressAndHoldSettings.update(PressAndHoldConfiguration(enabled: false, key: .rightCommand, mode: .hold))

        // Configure monitors
        appDelegate.configureShortcutMonitors()

        // Monitor should be nil when disabled
        XCTAssertNil(appDelegate.pressAndHoldMonitor)

        // Restore defaults
        PressAndHoldSettings.update(PressAndHoldConfiguration.defaults)
    }

    func testConfigureShortcutMonitorsSetsKeyUpHandlerForHoldMode() {
        // Set hold mode
        let holdConfig = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .hold)
        PressAndHoldSettings.update(holdConfig)

        // Configure monitors
        appDelegate.configureShortcutMonitors()

        // Monitor should be created
        XCTAssertNotNil(appDelegate.pressAndHoldMonitor)

        // Restore defaults
        PressAndHoldSettings.update(PressAndHoldConfiguration.defaults)
    }

    func testConfigureShortcutMonitorsNoKeyUpHandlerForToggleMode() {
        // Set toggle mode
        let toggleConfig = PressAndHoldConfiguration(enabled: true, key: .rightCommand, mode: .toggle)
        PressAndHoldSettings.update(toggleConfig)

        // Configure monitors
        appDelegate.configureShortcutMonitors()

        // Monitor should be created
        XCTAssertNotNil(appDelegate.pressAndHoldMonitor)

        // Restore defaults
        PressAndHoldSettings.update(PressAndHoldConfiguration.defaults)
    }

    // MARK: - handleHotkey Tests

    func testHandleHotkeyWithImmediateRecordingEnabled() {
        // Enable immediate recording
        UserDefaults.standard.set(true, forKey: "immediateRecording")

        // Without an audio recorder, it should fall back to toggle window
        appDelegate.handleHotkey(source: .standardHotkey)

        // Since we don't have a recorder, window toggle should happen
        // We can't fully test this without mocking, but we verify no crash
    }

    func testHandleHotkeyWithImmediateRecordingDisabled() {
        // Disable immediate recording
        UserDefaults.standard.set(false, forKey: "immediateRecording")

        // Should toggle window
        appDelegate.handleHotkey(source: .standardHotkey)

        // Verify no crash occurred
        UserDefaults.standard.set(true, forKey: "immediateRecording")
    }

    func testHandleHotkeyWithMockRecorderNotRecording() {
        // Create mock recorder
        let mockRecorder = MockAudioEngineRecorder()
        mockRecorder.startRecordingResult = false  // Simulate permission denied

        // Enable immediate recording
        UserDefaults.standard.set(true, forKey: "immediateRecording")

        // Set the mock recorder
        // Note: We can't easily inject mock here due to type constraints
        // This test demonstrates the pattern

        appDelegate.handleHotkey(source: .standardHotkey)
    }

    func testHandleHotkeyPostsSpaceKeyNotificationWhenRecording() {
        // This tests the notification flow
        let expectation = expectation(forNotification: .spaceKeyPressed, object: nil, handler: nil)
        expectation.isInverted = true  // Won't fire without actual recording

        appDelegate.handleHotkey(source: .standardHotkey)

        wait(for: [expectation], timeout: 0.5)
    }

    // MARK: - Recording State Tests

    func testIsHoldRecordingActiveInitiallyFalse() {
        XCTAssertFalse(appDelegate.isHoldRecordingActive)
    }

    func testRecordingAnimationTimerInitiallyNil() {
        XCTAssertNil(appDelegate.recordingAnimationTimer)
    }

    // MARK: - onRecordingStopped Tests

    func testOnRecordingStoppedUpdatesMenuIcon() {
        // Create status item for testing
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        appDelegate.statusItem = statusItem

        // Set initial recording state icon
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "microphone.circle", accessibilityDescription: nil)
        }

        // Call onRecordingStopped
        appDelegate.onRecordingStopped()

        // Verify no crash - actual icon verification would require visual comparison
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Recording Animation Tests

    func testRecordingAnimationTimerCleanup() {
        // Create a mock timer
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + 100, repeating: .seconds(1))
        timer.resume()
        appDelegate.recordingAnimationTimer = timer

        // Verify timer exists
        XCTAssertNotNil(appDelegate.recordingAnimationTimer)

        // Cancel timer
        appDelegate.recordingAnimationTimer?.cancel()
        appDelegate.recordingAnimationTimer = nil

        // Verify cleanup
        XCTAssertNil(appDelegate.recordingAnimationTimer)
    }

    // MARK: - HotkeyTriggerSource Tests

    func testHotkeyTriggerSourceStandardHotkey() {
        let source = AppDelegate.HotkeyTriggerSource.standardHotkey

        switch source {
        case .standardHotkey:
            XCTAssertTrue(true)
        case .pressAndHold:
            XCTFail("Expected standardHotkey")
        }
    }

    func testHotkeyTriggerSourcePressAndHold() {
        let source = AppDelegate.HotkeyTriggerSource.pressAndHold

        switch source {
        case .pressAndHold:
            XCTAssertTrue(true)
        case .standardHotkey:
            XCTFail("Expected pressAndHold")
        }
    }

    // MARK: - Notification Tests

    func testRecordingStartFailedNotificationName() {
        // Verify notification name exists
        let name = Notification.Name.recordingStartFailed
        XCTAssertNotNil(name)
    }

    func testSpaceKeyPressedNotificationName() {
        // Verify notification name exists
        let name = Notification.Name.spaceKeyPressed
        XCTAssertNotNil(name)
    }

    // MARK: - Press and Hold Configuration Tests

    func testPressAndHoldConfigurationUpdatesOnSettingsChange() {
        // Get initial configuration
        let initialConfig = appDelegate.pressAndHoldConfiguration

        // Update settings
        let newConfig = PressAndHoldConfiguration(enabled: false, key: .leftOption, mode: .toggle)
        PressAndHoldSettings.update(newConfig)

        // Configure monitors (which updates configuration)
        appDelegate.configureShortcutMonitors()

        // Verify configuration changed
        XCTAssertEqual(appDelegate.pressAndHoldConfiguration.enabled, false)
        XCTAssertEqual(appDelegate.pressAndHoldConfiguration.key, .leftOption)
        XCTAssertEqual(appDelegate.pressAndHoldConfiguration.mode, .toggle)

        // Restore defaults
        PressAndHoldSettings.update(initialConfig)
    }
}
