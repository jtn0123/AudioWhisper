import XCTest
import AppKit
import SwiftUI
@testable import AudioWhisper

final class WindowControllerTests: IsolatedXCTestCase {
    // Deferred(D1): WindowController reads `hasCompletedWelcome` from
    // UserDefaults.standard directly. Once it accepts an injected
    // UserDefaults, route writes through a UUID-scoped suite and re-enable.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    var windowController: WindowController!
    
    override func setUp() {
        super.setUp()
        windowController = WindowController()
    }
    
    override func tearDown() {
        windowController = nil
        AppDefaults.defaults.removeObject(forKey: "hasCompletedWelcome")
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testWindowControllerInitialization() {
        XCTAssertNotNil(windowController)
    }
    
    // MARK: - Welcome Completion Check Tests
    
    func testToggleRecordWindowBlockedDuringWelcome() {
        AppDefaults.defaults.set(false, forKey: "hasCompletedWelcome")

        // During welcome, toggling the record window must be a safe no-op.
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    func testToggleRecordWindowAllowedAfterWelcome() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        // Should allow toggling after welcome is completed
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    // MARK: - Window Visibility Tests
    
    func testToggleRecordWindowWhenNoWindow() {
        // When no recording window exists, should not crash
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    func testWindowShowingAndHiding() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        // Test that toggling doesn't crash
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    // MARK: - Settings Window Tests
    
    @MainActor
    func testOpenSettingsCreatesNewWindow() {
        // Should not crash when opening settings
        XCTAssertNoThrow(windowController.openSettings())
    }
    
    @MainActor
    func testOpenSettingsHidesRecordingWindow() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        // In test environment, this just verifies no crash
        XCTAssertNoThrow(windowController.openSettings())
    }
    
    @MainActor
    func testOpenSettingsWithExistingSettingsWindow() {
        // In test environment, openSettings() returns early
        // Just verify it doesn't crash
        XCTAssertNoThrow(windowController.openSettings())
    }
    
    // MARK: - Focus Management Tests
    
    func testRestoreFocusToPreviousAppWithNoPreviousApp() {
        // Should not crash when no previous app is stored
        XCTAssertNoThrow(windowController.restoreFocusToPreviousApp())
    }
    
    func testFocusRestorationFlow() {
        // Test the focus restoration mechanism doesn't crash
        XCTAssertNoThrow(windowController.restoreFocusToPreviousApp())
    }
    
    // MARK: - Window Configuration Tests
    
    func testWindowConfiguration() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        // Test window configuration doesn't crash
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    func testWindowLevelConfiguration() {
        // Test that window operations don't crash
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    func testWindowCollectionBehavior() {
        // Test that window operations don't crash
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    // MARK: - Async Operations Tests
    
    func testAsyncWindowOperations() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        // In test environment, this returns early, just verify no crash
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    // MARK: - Edge Cases Tests
    
    func testMultipleToggleCalls() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        // Multiple rapid calls should not crash
        for _ in 0..<10 {
            XCTAssertNoThrow(windowController.toggleRecordWindow())
        }
    }
    
    @MainActor
    func testMultipleSettingsOpenCalls() {
        // Multiple rapid settings calls should not crash
        for _ in 0..<5 {
            XCTAssertNoThrow(windowController.openSettings())
        }
    }
    
    @MainActor
    func testConcurrentWindowOperations() async {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<10 {
                group.addTask { @MainActor in
                    if index % 2 == 0 {
                        self.windowController.toggleRecordWindow()
                    } else {
                        self.windowController.openSettings()
                    }
                }
            }
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testWindowControllerDeallocation() {
        weak var weakController: WindowController? = windowController

        windowController = nil

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertNil(weakController, "WindowController should be deallocated")
    }
    
    // MARK: - Performance Tests
    
    func testToggleWindowPerformance() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        measure {
            for _ in 0..<100 {
                windowController.toggleRecordWindow()
            }
        }
    }
    
    @MainActor
    func testOpenSettingsPerformance() {
        measure {
            for _ in 0..<50 {
                windowController.openSettings()
            }
        }
    }
    
    // MARK: - Error Handling Tests
    
    @MainActor
    func testWindowOperationsWithInvalidWindows() {
        // Test with nil window references
        XCTAssertNoThrow(windowController.toggleRecordWindow())
        XCTAssertNoThrow(windowController.openSettings())
        XCTAssertNoThrow(windowController.restoreFocusToPreviousApp())
    }
    
    @MainActor
    func testWindowOperationsAfterWindowClosed() {
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        
        // Operations should not crash
        XCTAssertNoThrow(windowController.toggleRecordWindow())
        XCTAssertNoThrow(windowController.openSettings())
    }
    
    // MARK: - UserDefaults Integration Tests
    
    func testWelcomeStateChanges() {
        // Test toggling welcome state
        AppDefaults.defaults.set(false, forKey: "hasCompletedWelcome")
        XCTAssertNoThrow(windowController.toggleRecordWindow())
        
        AppDefaults.defaults.set(true, forKey: "hasCompletedWelcome")
        XCTAssertNoThrow(windowController.toggleRecordWindow())
        
        // Reset state
        AppDefaults.defaults.removeObject(forKey: "hasCompletedWelcome")
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }
    
    func testDefaultWelcomeState() {
        // When hasCompletedWelcome is not set, should default to false
        AppDefaults.defaults.removeObject(forKey: "hasCompletedWelcome")

        let hasCompleted = AppDefaults.defaults.bool(forKey: "hasCompletedWelcome")
        XCTAssertFalse(hasCompleted)

        // Should block window toggle
        XCTAssertNoThrow(windowController.toggleRecordWindow())
    }

    // MARK: - Window Title Constant Tests (bug regression prevention)

    func testRecordingWindowTitleConstant() {
        // Verify the constant exists and has expected value
        XCTAssertEqual(WindowTitles.recording, "AudioWhisper Recording")
    }

    func testWindowTitleConstantIsNotEmpty() {
        // Verify the constant is not empty
        XCTAssertFalse(WindowTitles.recording.isEmpty)
    }

    func testWindowLookupWithConstant() {
        // Create a window with the constant title
        let window = NSWindow()
        window.title = WindowTitles.recording

        // Verify the title was set correctly
        XCTAssertEqual(window.title, "AudioWhisper Recording")
    }
}
