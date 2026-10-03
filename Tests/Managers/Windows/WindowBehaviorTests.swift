import XCTest
import AppKit
@testable import AudioWhisper

/// The configuration that makes AudioWhisper's windows behave like a Mac
/// app's: normal windows that stay put and can be found with ⌘-Tab and the
/// Dock, and a recording window that floats over everything without getting in
/// the way.
///
/// None of these windows is shown — `defer: true` never asks the window server
/// for one — so this runs headless.
@MainActor
final class ActivationPolicyControllerTests: XCTestCase {
    private var applied: [NSApplication.ActivationPolicy] = []
    private var showing: Set<ObjectIdentifier> = []
    private var workspaceNotifications: NotificationCenter!
    private var appNotifications: NotificationCenter!
    private var controller: ActivationPolicyController!

    override func setUp() {
        super.setUp()
        applied = []
        showing = []
        workspaceNotifications = NotificationCenter()
        appNotifications = NotificationCenter()
        controller = ActivationPolicyController(
            applyPolicy: { [weak self] in self?.applied.append($0) },
            isOnActiveSpace: { [weak self] in self?.showing.contains(ObjectIdentifier($0)) ?? false },
            workspaceNotifications: workspaceNotifications,
            appNotifications: appNotifications
        )
    }

    func testWithNoWindowOpenItIsAMenuBarAccessory() {
        XCTAssertEqual(controller.policy, .accessory)
        XCTAssertEqual(applied, [], "nothing is applied until a window opens")
    }

    func testOpeningAWindowGivesTheAppADockIconAndACommandTabEntry() {
        controller.windowDidOpen(makeWindow())

        XCTAssertEqual(controller.policy, .regular)
        XCTAssertEqual(applied, [.regular])
    }

    func testItStaysARegularAppUntilTheLastWindowCloses() {
        let dashboard = makeWindow()
        let history = makeWindow()
        controller.windowDidOpen(dashboard)
        controller.windowDidOpen(history)

        controller.windowWillClose(dashboard)
        XCTAssertEqual(applied, [.regular], "History is still open")

        controller.windowWillClose(history)
        XCTAssertEqual(applied, [.regular, .accessory])
        XCTAssertEqual(controller.policy, .accessory)
    }

    /// `showDashboardWindow()` presents the same window every time it is asked.
    func testPresentingTheSameWindowAgainDoesNotCountItTwice() {
        let dashboard = makeWindow()
        controller.windowDidOpen(dashboard)
        controller.windowDidOpen(dashboard)

        controller.windowWillClose(dashboard)

        XCTAssertEqual(applied, [.regular, .accessory])
    }

    func testClosingAWindowItNeverSawChangesNothing() {
        controller.windowWillClose(makeWindow())

        XCTAssertEqual(applied, [])
    }

    // MARK: - The status menu

    /// The Dashboard is open on a desktop and the user is in a full-screen
    /// app. As a regular app, AudioWhisper's menu could not open there.
    func testClickingTheMenuBarIconAwayFromItsWindowsStepsAside() {
        controller.windowDidOpen(makeWindow())

        controller.statusMenuWillOpen()

        XCTAssertEqual(applied, [.regular, .accessory])
        XCTAssertEqual(controller.policy, .accessory)
    }

    func testClickingTheMenuBarIconBesideItsWindowKeepsTheDockIcon() {
        let dashboard = makeWindow()
        controller.windowDidOpen(dashboard)
        showing.insert(ObjectIdentifier(dashboard))

        controller.statusMenuWillOpen()

        XCTAssertEqual(applied, [.regular], "the menu opens there anyway; the Dock icon must not flicker")
    }

    func testWithNoWindowOpenTheMenuChangesNothing() {
        controller.statusMenuWillOpen()

        XCTAssertEqual(applied, [])
    }

    func testBackOnTheSpaceWithItsWindowItIsARegularAppAgain() {
        let dashboard = makeWindow()
        controller.windowDidOpen(dashboard)
        controller.statusMenuWillOpen()

        showing.insert(ObjectIdentifier(dashboard))
        workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(applied, [.regular, .accessory, .regular])
    }

    /// A minimised Dashboard comes back without a Space change.
    func testItsWindowBecomingKeyMakesItARegularAppAgain() {
        let dashboard = makeWindow()
        controller.windowDidOpen(dashboard)
        controller.statusMenuWillOpen()

        showing.insert(ObjectIdentifier(dashboard))
        appNotifications.post(name: NSWindow.didBecomeKeyNotification, object: dashboard)

        XCTAssertEqual(controller.policy, .regular)
    }

    /// Another Space without its windows is still away from them.
    func testASpaceChangeElsewhereLeavesItAnAccessory() {
        controller.windowDidOpen(makeWindow())
        controller.statusMenuWillOpen()

        workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        XCTAssertEqual(applied, [.regular, .accessory])
    }

    /// "Dashboard" chosen from the menu after stepping aside: the window is
    /// still open, but showing it makes the app regular again — and
    /// `WindowPresenter` has to wait for the move off the full-screen Space.
    func testShowingAnOpenWindowAfterSteppingAsideMakesItRegularAgain() {
        let dashboard = makeWindow()
        controller.windowDidOpen(dashboard)
        controller.statusMenuWillOpen()

        XCTAssertTrue(controller.windowDidOpen(dashboard))
        XCTAssertEqual(applied, [.regular, .accessory, .regular])
    }

    func testShowingAWindowOfARegularAppReportsNoChange() {
        controller.windowDidOpen(makeWindow())

        XCTAssertFalse(controller.windowDidOpen(makeWindow()))
    }

    func testClosingTheLastWindowAfterSteppingAsideAppliesNothingMore() {
        let dashboard = makeWindow()
        controller.windowDidOpen(dashboard)
        controller.statusMenuWillOpen()

        controller.windowWillClose(dashboard)

        XCTAssertEqual(applied, [.regular, .accessory])
    }

    private func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                 styleMask: [.titled, .closable], backing: .buffered, defer: true)
    }
}

@MainActor
final class StandardWindowTests: XCTestCase {
    func testANormalWindowStaysOnItsSpaceAndCanGoFullScreen() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: true)

        StandardWindow.configure(window, frameAutosaveName: nil)

        XCTAssertEqual(window.collectionBehavior, [.fullScreenPrimary])
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace),
                       "it must not follow the user to whichever Space is active")
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary),
                       "it must not open as an overlay on another app's full-screen window")
        XCTAssertEqual(window.tabbingMode, .disallowed)
        XCTAssertFalse(window.isReleasedWhenClosed, "its manager holds it and releases it on close")
    }

    func testClosingTellsTheOwnerItHasGone() {
        var closed = false
        let delegate = StandardWindowDelegate { closed = true }
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)

        delegate.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

        XCTAssertTrue(closed)
    }
}

@MainActor
final class RecordingWindowStyleTests: XCTestCase {
    func testItFloatsOnEverySpaceWithoutJoiningWindowCycling() {
        let window = ChromelessWindow(contentRect: NSRect(origin: .zero, size: LayoutMetrics.RecordingWindow.size),
                                      styleMask: [.borderless], backing: .buffered, defer: true)

        RecordingWindowStyle.configure(window)

        XCTAssertEqual(window.level, .floating)
        XCTAssertEqual(window.collectionBehavior, [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle])
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenPrimary),
                       "the overlay must not be able to go full screen itself")
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertFalse(window.hidesOnDeactivate, "it stays up while another app is active")
        XCTAssertFalse(window.canHide, "hiding the app must not hide a recording in progress")
    }

    func testAWindowAlreadyOnTheActiveScreenStaysWhereTheUserPutIt() {
        let laptop = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = NSRect(x: 80, y: 600, width: 300, height: 120)

        XCTAssertEqual(RecordingWindowStyle.frameOrigin(for: frame, on: laptop), frame.origin)
    }

    func testAWindowOnAnotherScreenIsCentredOnTheActiveOne() {
        let external = NSRect(x: 1440, y: 0, width: 1920, height: 1055)
        let onLaptop = NSRect(x: 570, y: 377, width: 300, height: 120)

        let origin = RecordingWindowStyle.frameOrigin(for: onLaptop, on: external)

        XCTAssertEqual(origin, NSPoint(x: 1440 + 960 - 150, y: 528 - 60))
    }

    /// The window counts as on a screen by its centre, so one that only
    /// overlaps the active screen's edge still moves onto it.
    func testAWindowOverlappingTheActiveScreenByItsEdgeIsMovedOntoIt() {
        let laptop = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let mostlyOffscreen = NSRect(x: 1300, y: 400, width: 300, height: 120)

        let origin = RecordingWindowStyle.frameOrigin(for: mostlyOffscreen, on: laptop)

        XCTAssertEqual(origin, NSPoint(x: 570, y: 378))
    }
}

final class RecordingWindowKeyRoutingTests: XCTestCase {
    func testOnlyKeysAimedAtTheRecordingWindowAreRecordingCommands() {
        XCTAssertTrue(KeyboardEventHandler.isForRecordingWindow(eventWindowNumber: 42, recordingWindowNumber: 42))
    }

    /// The Dashboard opens beside a recording window that is showing an error;
    /// typing in it must type in it.
    func testAKeyTypedIntoAnotherWindowIsLeftAlone() {
        XCTAssertFalse(KeyboardEventHandler.isForRecordingWindow(eventWindowNumber: 7, recordingWindowNumber: 42))
    }

    func testAKeyWithNoWindowIsLeftAlone() {
        XCTAssertFalse(KeyboardEventHandler.isForRecordingWindow(eventWindowNumber: 0, recordingWindowNumber: 42))
    }

    /// A window the window server has not numbered yet reports 0, as does an
    /// event with no window; they must not be taken for a match.
    func testAnUnnumberedRecordingWindowMatchesNothing() {
        XCTAssertFalse(KeyboardEventHandler.isForRecordingWindow(eventWindowNumber: 0, recordingWindowNumber: 0))
    }
}
