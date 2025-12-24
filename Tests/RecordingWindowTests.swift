import XCTest
import AppKit
@testable import AudioWhisper

final class RecordingWindowTests: XCTestCase {

    // MARK: - Window Title Tests

    func testWindowTitleIsCorrect() {
        XCTAssertEqual(WindowTitles.recording, "AudioWhisper Recording")
    }

    func testWindowTitleIsNotEmpty() {
        XCTAssertFalse(WindowTitles.recording.isEmpty)
    }

    func testWindowCanBeLookedUpByTitle() {
        let window = NSWindow()
        window.title = WindowTitles.recording

        let found = [window].first { $0.title == WindowTitles.recording }
        XCTAssertNotNil(found, "Should find window by title")
    }

    // MARK: - Window Configuration Tests

    func testWindowConfigurationForRecording() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Configure like recording window
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertEqual(window.level, .floating)
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    func testBorderlessWindowStyle() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(window.styleMask.contains(.borderless))
        XCTAssertFalse(window.styleMask.contains(.titled))
    }

    // MARK: - Window Visibility Tests

    func testWindowVisibilityToggle() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Start hidden
        XCTAssertFalse(window.isVisible)

        // Hide explicitly
        window.orderOut(nil)
        XCTAssertFalse(window.isVisible)
    }

    func testWindowOrderOutHidesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.orderOut(nil)
        XCTAssertFalse(window.isVisible)
    }

    // MARK: - Window Level Tests

    func testWindowLevelProgression() {
        let window = NSWindow()

        // Recording window uses floating level
        window.level = .floating
        XCTAssertEqual(window.level, .floating)

        // Can change to other levels
        window.level = .normal
        XCTAssertEqual(window.level, .normal)

        // Can set to screen saver level
        window.level = .screenSaver
        XCTAssertEqual(window.level, .screenSaver)
    }

    func testFloatingWindowLevelIsAboveNormal() {
        XCTAssertGreaterThan(NSWindow.Level.floating.rawValue, NSWindow.Level.normal.rawValue)
    }

    // MARK: - Collection Behavior Tests

    func testCollectionBehaviorForAllSpaces() {
        let window = NSWindow()

        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testCollectionBehaviorCanBeModified() {
        let window = NSWindow()

        window.collectionBehavior = []
        XCTAssertFalse(window.collectionBehavior.contains(.canJoinAllSpaces))

        window.collectionBehavior = [.canJoinAllSpaces]
        XCTAssertTrue(window.collectionBehavior.contains(.canJoinAllSpaces))
    }

    // MARK: - Window Frame Tests

    func testWindowFrameCanBeSet() {
        let window = NSWindow()
        let frame = NSRect(x: 100, y: 100, width: 400, height: 200)

        window.setFrame(frame, display: false)

        XCTAssertEqual(window.frame.width, 400)
        XCTAssertEqual(window.frame.height, 200)
    }

    func testWindowCenteringDoesNotCrash() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        XCTAssertNoThrow(window.center())
    }

    // MARK: - Window Delegate Tests

    func testWindowDelegateSetup() {
        // Test that delegate can be set without crash
        let window = NSWindow()

        class TestDelegate: NSObject, NSWindowDelegate {
            func windowWillClose(_ notification: Notification) {}
        }

        let delegate = TestDelegate()
        window.delegate = delegate

        XCTAssertNotNil(window.delegate)
    }

    func testWindowShouldCloseDelegate() {
        let window = NSWindow()

        class PreventCloseDelegate: NSObject, NSWindowDelegate {
            func windowShouldClose(_ sender: NSWindow) -> Bool {
                return false
            }
        }

        let delegate = PreventCloseDelegate()
        window.delegate = delegate

        // windowShouldClose should return false
        XCTAssertFalse(delegate.windowShouldClose(window))
    }

    // MARK: - Background Color Tests

    func testClearBackgroundColor() {
        let window = NSWindow()
        window.backgroundColor = .clear

        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func testOpaqueBackgroundColor() {
        let window = NSWindow()
        window.isOpaque = false
        window.backgroundColor = NSColor(white: 0, alpha: 0.8)

        XCTAssertFalse(window.isOpaque)
    }

    // MARK: - Window Alpha Tests

    func testWindowAlphaValue() {
        let window = NSWindow()

        window.alphaValue = 1.0
        XCTAssertEqual(window.alphaValue, 1.0, accuracy: 0.01)

        window.alphaValue = 0.5
        XCTAssertEqual(window.alphaValue, 0.5, accuracy: 0.01)

        window.alphaValue = 0.0
        XCTAssertEqual(window.alphaValue, 0.0, accuracy: 0.01)
    }

    // MARK: - Movable Window Tests

    func testMovableByWindowBackground() {
        let window = NSWindow()

        window.isMovableByWindowBackground = true
        XCTAssertTrue(window.isMovableByWindowBackground)

        window.isMovableByWindowBackground = false
        XCTAssertFalse(window.isMovableByWindowBackground)
    }

    // MARK: - Content View Tests

    func testWindowContentViewAssignment() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        window.contentView = contentView

        XCTAssertEqual(window.contentView, contentView)
    }
}
