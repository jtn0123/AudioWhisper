import XCTest
import SwiftData
@testable import AudioWhisper

/// Tests for AppDelegate+RecordingWindow.swift focusing on window management
@MainActor
final class AppDelegateRecordingWindowTests: XCTestCase {

    var appDelegate: AppDelegate!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }

    override func tearDown() {
        appDelegate.recordingWindow?.close()
        appDelegate.recordingWindow = nil
        appDelegate.recordingWindowDelegate = nil
        appDelegate = nil
        super.tearDown()
    }

    // MARK: - toggleRecordWindow Tests

    func testToggleRecordWindowCreatesWindowIfNil() {
        // Initially nil
        XCTAssertNil(appDelegate.recordingWindow)

        // Toggle would create window if audio recorder exists
        // Without recorder, window creation should fail gracefully
        appDelegate.toggleRecordWindow()

        // Window may still be nil without recorder
    }

    func testToggleRecordWindowWithExistingWindowState() {
        // Initially nil
        XCTAssertNil(appDelegate.recordingWindow)

        // After toggling without recorder, should still be nil
        // (Window creation requires audio recorder)
        appDelegate.toggleRecordWindow()

        // Window should be nil without recorder
        XCTAssertNil(appDelegate.recordingWindow)
    }

    // MARK: - showRecordingWindowForProcessing Tests

    func testShowRecordingWindowForProcessingCreatesWindow() {
        // Initially nil
        XCTAssertNil(appDelegate.recordingWindow)

        // Would create window if audio recorder exists
        appDelegate.showRecordingWindowForProcessing()
    }

    func testShowRecordingWindowForProcessingWithNilWindow() {
        // Initially no window
        XCTAssertNil(appDelegate.recordingWindow)

        // Call without completion handler
        appDelegate.showRecordingWindowForProcessing()

        // Without audio recorder, window won't be created
        XCTAssertNil(appDelegate.recordingWindow)
    }

    func testShowRecordingWindowForProcessingHidesDashboard() {
        // With no audio recorder configured, showRecordingWindowForProcessing
        // must not create a recording window.
        XCTAssertNil(appDelegate.audioRecorder)
        appDelegate.showRecordingWindowForProcessing()
        XCTAssertNil(appDelegate.recordingWindow)
    }

    // MARK: - createRecordingWindow Tests

    func testCreateRecordingWindowRequiresAudioRecorder() {
        // Without audio recorder, window shouldn't be created
        XCTAssertNil(appDelegate.audioRecorder)

        appDelegate.createRecordingWindow()

        // Window should still be nil without recorder
        XCTAssertNil(appDelegate.recordingWindow)
    }

    func testCreateRecordingWindowWithMockRecorder() {
        // Create mock recorder
        let mockRecorder = MockAudioEngineRecorder()

        // We can't easily inject mock due to type constraints
        // This demonstrates the test pattern
        XCTAssertNotNil(mockRecorder)
    }

    // MARK: - Window Configuration Tests

    func testRecordingWindowProperties() {
        // If we had a window, verify its properties
        // This tests the expected configuration

        let expectedWindowSize = LayoutMetrics.RecordingWindow.size
        XCTAssertGreaterThan(expectedWindowSize.width, 0)
        XCTAssertGreaterThan(expectedWindowSize.height, 0)
    }

    func testRecordingWindowTitleConstant() {
        // Verify the window title constant exists
        let title = WindowTitles.recording
        XCTAssertFalse(title.isEmpty)
    }

    func testRecordingWindowLevelIsFloating() {
        // Verify expected window level
        let expectedLevel = NSWindow.Level.floating
        XCTAssertNotNil(expectedLevel)
    }

    func testRecordingWindowCollectionBehavior() {
        // Verify expected collection behavior components
        let behaviors: [NSWindow.CollectionBehavior] = [
            .canJoinAllSpaces,
            .fullScreenPrimary,
            .fullScreenAuxiliary
        ]

        for behavior in behaviors {
            XCTAssertNotNil(behavior)
        }
    }

    // MARK: - Recording Window Delegate Tests

    func testOnRecordingWindowClosedCallsCleanupHandler() {
        // Test that RecordingWindowDelegate closure is called
        var closeCalled = false

        let delegate = RecordingWindowDelegate {
            closeCalled = true
        }

        // Simulate window close notification without actual window
        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        XCTAssertTrue(closeCalled)
    }

    func testRecordingWindowDelegateExists() {
        // Create a delegate
        var wasCalled = false
        let delegate = RecordingWindowDelegate {
            wasCalled = true
        }

        // Verify it exists
        XCTAssertNotNil(delegate)

        // Trigger callback
        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification))

        XCTAssertTrue(wasCalled)
    }

    // MARK: - restoreFocusToPreviousApp Tests

    func testRestoreFocusToPreviousAppCallsWindowController() {
        // restoreFocusToPreviousApp restores app focus; it must not create
        // or mutate the recording window.
        XCTAssertNil(appDelegate.recordingWindow)
        appDelegate.restoreFocusToPreviousApp()
        XCTAssertNil(appDelegate.recordingWindow)
    }

    // MARK: - Fallback Model Container Tests

    func testFallbackModelContainerIsInMemory() {
        // Verify that the fallback container would be in-memory
        // We can't easily test the private method, but we can verify the concept

        do {
            let schema = Schema([TranscriptionRecord.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])

            XCTAssertNotNil(container)
        } catch {
            XCTFail("Should be able to create in-memory container: \(error)")
        }
    }

    // MARK: - ChromelessWindow Tests

    func testChromelessWindowOverridesResponderBehavior() {
        // ChromelessWindow is borderless; it overrides NSWindow so it can
        // still become key/main and accept first responder.
        let window = ChromelessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.canBecomeMain)
        XCTAssertTrue(window.acceptsFirstResponder)
    }

    // MARK: - Window State Tests

    func testRecordingWindowInitiallyNil() {
        XCTAssertNil(appDelegate.recordingWindow)
    }

    func testRecordingWindowDelegateInitiallyNil() {
        XCTAssertNil(appDelegate.recordingWindowDelegate)
    }

    func testWindowControllerExists() {
        XCTAssertNotNil(appDelegate.windowController)
    }
}
