import XCTest
import AppKit
@testable import AudioWhisper

@MainActor
final class KeyboardEventHandlerTests: XCTestCase {
    private var handler: KeyboardEventHandler!
    private var window: NSWindow!

    override func setUp() {
        super.setUp()
        handler = KeyboardEventHandler(isTestEnvironment: true)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = WindowTitles.recording
    }

    override func tearDown() {
        window = nil
        handler = nil
        super.tearDown()
    }

    // MARK: - Helper

    private func keyEvent(
        characters: String,
        charactersIgnoringModifiers: String? = nil,
        modifiers: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 0,
        windowNumber: Int = 0
    ) -> NSEvent? {
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers ?? characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }

    // MARK: - Key Handling
    
    func testSpaceKeyPostsNotificationAndConsumesEvent() {
        let expectation = expectation(forNotification: .spaceKeyPressed, object: nil)
        guard let event = keyEvent(characters: " ", keyCode: 49) else {
            XCTFail("Failed to create key event")
            return
        }

        let result = handler.handleKeyEvent(event, for: window)

        XCTAssertNil(result)
        wait(for: [expectation], timeout: 1)
    }

    func testEscapeKeyPostsNotificationAndConsumesEvent() {
        let expectation = expectation(forNotification: .escapeKeyPressed, object: nil)
        let escapeCharacter = String(Character(UnicodeScalar(27)!))
        guard let event = keyEvent(characters: escapeCharacter, keyCode: 53) else {
            XCTFail("Failed to create key event")
            return
        }

        let result = handler.handleKeyEvent(event, for: window)

        XCTAssertNil(result)
        wait(for: [expectation], timeout: 1)
    }

    func testReturnKeyPostsNotificationAndConsumesEvent() {
        let expectation = expectation(forNotification: .returnKeyPressed, object: nil)
        guard let event = keyEvent(characters: "\r", keyCode: 36) else {
            XCTFail("Failed to create key event")
            return
        }

        let result = handler.handleKeyEvent(event, for: window)

        XCTAssertNil(result)
        wait(for: [expectation], timeout: 1)
    }

    func testCommandCommaConsumesEvent() {
        guard let event = keyEvent(characters: ",", modifiers: [.command], keyCode: 0) else {
            XCTFail("Failed to create key event")
            return
        }

        let result = handler.handleKeyEvent(event, for: window)

        XCTAssertNil(result, "Command+Comma should be consumed to open dashboard")
    }

    func testOtherCommandShortcutsAreBlocked() {
        guard let event = keyEvent(characters: "c", modifiers: [.command], keyCode: 8) else {
            XCTFail("Failed to create key event")
            return
        }

        let result = handler.handleKeyEvent(event, for: window)

        XCTAssertNil(result, "Command-modified keys should be blocked when recording window is visible")
    }

    func testNonCommandKeysPassThrough() {
        guard let event = keyEvent(characters: "a", keyCode: 0) else {
            XCTFail("Failed to create key event")
            return
        }

        let result = handler.handleKeyEvent(event, for: window)

        XCTAssertNotNil(result, "Non-command keys should pass through")
    }

    // MARK: - Keys sent to AudioWhisper (local monitor)

    func testAKeyAimedAtTheRecordingWindowGoesNoFurther() throws {
        let recording = numberedWindow()
        let event = try XCTUnwrap(keyEvent(characters: "a", windowNumber: recording.windowNumber))

        XCTAssertNil(handler.handleLocalKeyEvent(event, recordingWindow: recording),
                     "the recording window has no text input for the key to reach")
    }

    func testARecordingCommandAimedAtTheRecordingWindowIsCarriedOut() throws {
        let recording = numberedWindow()
        let escape = String(Character(UnicodeScalar(27)))
        let event = try XCTUnwrap(keyEvent(characters: escape, keyCode: 53, windowNumber: recording.windowNumber))
        let dismissed = expectation(forNotification: .escapeKeyPressed, object: nil)

        _ = handler.handleLocalKeyEvent(event, recordingWindow: recording)

        wait(for: [dismissed], timeout: 1)
    }

    /// The Dashboard opens beside a recording window showing an error: a key
    /// typed into the Dashboard must reach the Dashboard.
    func testAKeyAimedAtAnotherWindowIsPassedOn() throws {
        let recording = numberedWindow()
        let dashboard = numberedWindow()
        let event = try XCTUnwrap(keyEvent(characters: " ", keyCode: 49, windowNumber: dashboard.windowNumber))

        XCTAssertTrue(handler.handleLocalKeyEvent(event, recordingWindow: recording) === event)
    }

    func testWithNoRecordingWindowEveryKeyIsPassedOn() throws {
        let event = try XCTUnwrap(keyEvent(characters: " ", keyCode: 49, windowNumber: numberedWindow().windowNumber))

        XCTAssertTrue(handler.handleLocalKeyEvent(event, recordingWindow: nil) === event)
    }

    /// A window that is not deferred has a window number before it is shown.
    private func numberedWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        XCTAssertGreaterThan(window.windowNumber, 0)
        return window
    }
}
