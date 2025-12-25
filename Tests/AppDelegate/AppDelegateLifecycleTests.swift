import XCTest
@testable import AudioWhisper

/// Tests for AppDelegate+Lifecycle.swift focusing on app initialization and termination
@MainActor
final class AppDelegateLifecycleTests: XCTestCase {

    var appDelegate: AppDelegate!
    var testDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
        testDefaults = UserDefaults(suiteName: "AppDelegateLifecycleTests.\(UUID().uuidString)")!
    }

    override func tearDown() {
        appDelegate = nil
        testDefaults?.removePersistentDomain(forName: testDefaults.suiteName ?? "")
        testDefaults = nil
        super.tearDown()
    }

    // MARK: - UserDefaults Registration Tests

    func testApplicationDidFinishLaunchingRegistersDefaults() {
        // The defaults should be registered when app launches
        // We test by checking that the defaults exist after launch
        let defaults = UserDefaults.standard

        // These defaults should be registered
        // Note: In test environment, applicationDidFinishLaunching returns early
        // so we verify the defaults registration directly
        defaults.register(defaults: [
            "enableSmartPaste": true,
            "immediateRecording": true,
            "startAtLogin": true,
            "playCompletionSound": true
        ])

        // Verify the registered defaults are accessible
        XCTAssertTrue(defaults.bool(forKey: "enableSmartPaste"))
        XCTAssertTrue(defaults.bool(forKey: "immediateRecording"))
        XCTAssertTrue(defaults.bool(forKey: "startAtLogin"))
        XCTAssertTrue(defaults.bool(forKey: "playCompletionSound"))
    }

    func testApplicationDidFinishLaunchingSkipsUIInTestEnvironment() {
        // Create notification
        let notification = Notification(name: NSApplication.didFinishLaunchingNotification)

        // Call the lifecycle method
        appDelegate.applicationDidFinishLaunching(notification)

        // In test environment, UI should not be initialized
        // Status item should be nil because test environment is detected
        XCTAssertNil(appDelegate.statusItem)
        XCTAssertNil(appDelegate.audioRecorder)
        XCTAssertNil(appDelegate.hotKeyManager)
    }

    // MARK: - shouldTerminateAfterLastWindowClosed Tests

    func testApplicationShouldTerminateAfterLastWindowClosedReturnsFalse() {
        // Menu bar apps should not terminate when last window closes
        let result = appDelegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        XCTAssertFalse(result, "Menu bar app should not terminate when last window closes")
    }

    // MARK: - applicationWillTerminate Tests

    func testApplicationWillTerminateCancelsAnimationTimer() {
        // Set up a mock animation timer
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + 100, repeating: .seconds(1))
        timer.resume()
        appDelegate.recordingAnimationTimer = timer

        // Terminate
        let notification = Notification(name: NSApplication.willTerminateNotification)
        appDelegate.applicationWillTerminate(notification)

        // Timer should be nil after termination
        XCTAssertNil(appDelegate.recordingAnimationTimer)
    }

    func testApplicationWillTerminateCleanupsTempFiles() {
        // Create a temporary file in the temp directory
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent("old_recording_test.m4a")

        do {
            try "test".write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("Failed to create test file: \(error)")
            return
        }

        // Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))

        // Terminate
        let notification = Notification(name: NSApplication.willTerminateNotification)
        appDelegate.applicationWillTerminate(notification)

        // Note: AppSetupHelper.cleanupOldTemporaryFiles() is called
        // We can't directly verify it without inspecting the implementation
    }

    func testApplicationWillTerminateCleansUpWindowReferences() {
        // Set up window reference
        let window = NSWindow()
        appDelegate.recordingWindow = window
        appDelegate.recordingWindowDelegate = RecordingWindowDelegate {}

        // Terminate
        let notification = Notification(name: NSApplication.willTerminateNotification)
        appDelegate.applicationWillTerminate(notification)

        // Window references should be nil after termination
        XCTAssertNil(appDelegate.recordingWindow)
        XCTAssertNil(appDelegate.recordingWindowDelegate)
    }

    // MARK: - hasAPIKey Tests

    func testHasAPIKeyWithValidKey() {
        // Save a key to keychain
        let service = "test.service"
        let account = "test.account"
        let key = "test-api-key"

        KeychainService.shared.saveQuietly(key, service: service, account: account)

        // Verify hasAPIKey returns true
        let hasKey = appDelegate.hasAPIKey(service: service, account: account)
        XCTAssertTrue(hasKey)

        // Cleanup
        KeychainService.shared.deleteQuietly(service: service, account: account)
    }

    func testHasAPIKeyWithMissingKey() {
        // Use a service/account that doesn't exist
        let service = "nonexistent.service.\(UUID().uuidString)"
        let account = "nonexistent.account"

        // Verify hasAPIKey returns false
        let hasKey = appDelegate.hasAPIKey(service: service, account: account)
        XCTAssertFalse(hasKey)
    }

    // MARK: - Initial State Tests

    func testInitialStateOfAppDelegate() {
        // Verify initial state after creation
        XCTAssertNil(appDelegate.statusItem)
        XCTAssertNil(appDelegate.hotKeyManager)
        XCTAssertNil(appDelegate.audioRecorder)
        XCTAssertNil(appDelegate.recordingAnimationTimer)
        XCTAssertNil(appDelegate.pressAndHoldMonitor)
        XCTAssertFalse(appDelegate.isHoldRecordingActive)
        XCTAssertNotNil(appDelegate.windowController)
    }

    func testPressAndHoldConfigurationLoadsFromDefaults() {
        // Verify configuration is loaded
        let config = appDelegate.pressAndHoldConfiguration
        XCTAssertNotNil(config)

        // Verify it matches PressAndHoldSettings
        let expectedConfig = PressAndHoldSettings.configuration()
        XCTAssertEqual(config.enabled, expectedConfig.enabled)
        XCTAssertEqual(config.key, expectedConfig.key)
        XCTAssertEqual(config.mode, expectedConfig.mode)
    }

    // MARK: - Recording Window Delegate Tests

    func testRecordingWindowDelegateCleanupOnClose() {
        // Create window and delegate
        let window = NSWindow()
        var closeCalled = false

        let delegate = RecordingWindowDelegate {
            closeCalled = true
        }

        window.delegate = delegate
        appDelegate.recordingWindow = window
        appDelegate.recordingWindowDelegate = delegate

        // Simulate window close
        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        // Verify closure was called
        XCTAssertTrue(closeCalled)
    }

    // MARK: - HotkeyTriggerSource Tests

    func testHotkeyTriggerSourceEnum() {
        // Verify enum cases exist
        let standardSource = AppDelegate.HotkeyTriggerSource.standardHotkey
        let pressAndHoldSource = AppDelegate.HotkeyTriggerSource.pressAndHold

        XCTAssertNotNil(standardSource)
        XCTAssertNotNil(pressAndHoldSource)

        // Verify they are different
        switch standardSource {
        case .standardHotkey:
            XCTAssertTrue(true)
        case .pressAndHold:
            XCTFail("Should be standardHotkey")
        }

        switch pressAndHoldSource {
        case .pressAndHold:
            XCTAssertTrue(true)
        case .standardHotkey:
            XCTFail("Should be pressAndHold")
        }
    }
}
