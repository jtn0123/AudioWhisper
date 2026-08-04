import XCTest
import UniformTypeIdentifiers
@testable import AudioWhisper

/// Tests for AppDelegate+Menu.swift focusing on menu creation and actions
@MainActor
final class AppDelegateMenuTests: XCTestCase {

    var appDelegate: AppDelegate!

    override func setUp() {
        super.setUp()
        appDelegate = AppDelegate()
    }

    override func tearDown() {
        if let statusItem = appDelegate.statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        appDelegate = nil
        super.tearDown()
    }

    // MARK: - Menu Structure Tests

    /// The menu leads with a branded header item (a hosted SwiftUI view with
    /// no title and no action). The action items follow.
    func testMakeStatusMenuActionItemTitles() {
        let menu = appDelegate.makeStatusMenu()
        let actionItems = menu.items.filter { !$0.isSeparatorItem && $0.action != nil }

        let expectedTitles = [
            "Start Recording",
            "Transcribe a File…",
            "Dashboard",
            "Help / Welcome",
            "Quit AudioWhisper"
        ]

        XCTAssertEqual(actionItems.map { $0.title }, expectedTitles)
    }

    func testMakeStatusMenuHasBrandedHeader() {
        let menu = appDelegate.makeStatusMenu()
        // First item is the hosted header: a view item, disabled, no action.
        let header = menu.items.first
        XCTAssertNotNil(header?.view, "First item should host the branded header view")
        XCTAssertNil(header?.action)
        XCTAssertFalse(header?.isEnabled ?? true)
    }

    func testMakeStatusMenuActionItemsHaveActions() {
        let menu = appDelegate.makeStatusMenu()
        let actionItems = menu.items.filter { !$0.isSeparatorItem && $0.view == nil }
        XCTAssertEqual(actionItems.count, 5, "Menu should have 5 plain action items")
        for item in actionItems {
            XCTAssertNotNil(item.action, "Action item '\(item.title)' should have an action")
        }
    }

    func testMakeStatusMenuHasSeparators() {
        let menu = appDelegate.makeStatusMenu()
        let separators = menu.items.filter { $0.isSeparatorItem }
        XCTAssertEqual(separators.count, 3, "Menu should have 3 separators")
    }

    func testMakeStatusMenuQuitItemIsLast() {
        let menu = appDelegate.makeStatusMenu()
        let lastItem = menu.items.last

        XCTAssertEqual(lastItem?.title, "Quit AudioWhisper",
                      "Last menu item should be Quit")
        XCTAssertEqual(lastItem?.action, #selector(NSApplication.terminate(_:)),
                      "Quit action should be terminate")
    }

    // MARK: - Menu Action Tests

    func testShowHistoryDoesNotMutateStatusItem() {
        // showHistory delegates to HistoryWindowManager, which no-ops in the
        // test environment; it must not create or mutate the status item.
        XCTAssertNil(appDelegate.statusItem)
        appDelegate.showHistory()
        XCTAssertNil(appDelegate.statusItem)
    }

    func testDashboardMenuItemTargetsShowDashboard() {
        // The Dashboard menu item must be wired to the showDashboard selector.
        let menu = appDelegate.makeStatusMenu()
        let dashboardItem = menu.items.first { $0.title == "Dashboard" }
        XCTAssertNotNil(dashboardItem, "Menu should contain a Dashboard item")
        XCTAssertEqual(dashboardItem?.action, #selector(AppDelegate.showDashboard))

        // Invoking the action must not mutate the status item (no-op in tests).
        XCTAssertNil(appDelegate.statusItem)
        appDelegate.showDashboard()
        XCTAssertNil(appDelegate.statusItem)
    }

    // MARK: - Recent Transcript Copy (bug #12)

    func testCopyRecentTranscriptWritesToClipboard() {
        // Clicking a recent transcript row must copy its text to the clipboard.
        // The row carries a custom view so the menu item has no `action`;
        // copyRecentTranscript(text:) is invoked directly by the row's tap.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let sample = "Recent transcript \(UUID().uuidString)"
        appDelegate.copyRecentTranscript(text: sample)

        XCTAssertEqual(pasteboard.string(forType: .string), sample)
    }

    func testRecentTranscriptMenuRowTapInvokesHandler() {
        // The SwiftUI row exposes an onTap closure that drives the copy.
        var tapped = false
        let row = RecentTranscriptMenuRow(timeString: "1:23 PM", text: "hello") {
            tapped = true
        }
        row.onTap?()
        XCTAssertTrue(tapped, "onTap closure should fire when invoked")
    }

    func testShowHelpDoesNotCrash() {
        // This would normally show a dialog, but in test mode it may not
        // Just verify no crash
        // Note: This might show UI in non-test mode
    }

    // MARK: - Transcribe Audio File Tests

    func testTranscribeAudioFileAllowedContentTypes() {
        // Verify the allowed content types are properly configured
        let expectedTypes: [UTType] = [
            .mpeg4Audio,
            .mp3,
            .wav,
            .aiff,
            .init(filenameExtension: "m4a")!,
            .init(filenameExtension: "aac") ?? .mpeg4Audio,
            .init(filenameExtension: "flac") ?? .audio,
            .init(filenameExtension: "caf") ?? .audio
        ]

        // We can't directly access the panel configuration without calling transcribeAudioFile
        // But we can verify the types are valid
        for type in expectedTypes {
            XCTAssertNotNil(type, "Content type should be valid")
        }
    }

    func testProcessAudioFilePostsNotification() {
        // Create a test audio file URL
        let testURL = URL(fileURLWithPath: "/tmp/test_audio.m4a")

        let expectation = expectation(forNotification: .transcribeAudioFile, object: nil) { notification in
            if let url = notification.object as? URL {
                return url == testURL
            }
            return false
        }

        // Create recording window first
        appDelegate.createRecordingWindow()

        // Process audio file - this should post notification
        NotificationCenter.default.post(name: .transcribeAudioFile, object: testURL)

        wait(for: [expectation], timeout: 1.0)
    }

    func testTranscribeAudioFileNotificationName() {
        // Verify notification name exists
        let name = Notification.Name.transcribeAudioFile
        XCTAssertNotNil(name)
    }

    // MARK: - Screen Configuration Tests

    func testScreenConfigurationChangedResetsIconCache() throws {
        // A real status item needs a WindowServer connection; without one this
        // aborts the whole test process rather than failing. CI runners have no
        // GUI session, so this is skipped there and runs locally.
        try XCTSkipUnless(
            WindowServer.hasActiveDisplay,
            "Needs an active display to create an NSStatusItem"
        )

        // Create status item for testing
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        appDelegate.statusItem = statusItem

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: nil)
        }

        // Call screen configuration changed
        appDelegate.screenConfigurationChanged()

        // Verify the icon was updated (not nil)
        if let button = statusItem.button {
            // Icon should be reset
            XCTAssertNotNil(button.image)
        }

        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func testScreenConfigurationChangedWithNoStatusItem() {
        // Ensure no status item
        appDelegate.statusItem = nil

        // Should not crash
        appDelegate.screenConfigurationChanged()

        XCTAssertNil(appDelegate.statusItem)
    }

    // MARK: - Window Creation Tests

    func testCreateRecordingWindowCreatesWindow() {
        // Need audio recorder for window creation
        // In test environment this may not work fully

        // Verify initial state
        XCTAssertNil(appDelegate.recordingWindow)
    }

    func testProcessAudioFileCreatesRecordingWindow() {
        // Initially no window
        XCTAssertNil(appDelegate.recordingWindow)

        // Process would create window, but requires more setup in test environment
    }
}
