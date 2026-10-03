import XCTest
import AppKit
@testable import AudioWhisper

/// When the Dashboard, History and Welcome windows come on screen. The
/// timings here are the ones measured on a real full-screen Space: the menu
/// bar click activates AudioWhisper without leaving it, and becoming a regular
/// app moves to a desktop about 0.3 s later.
///
/// Nothing is put on screen: ordering in, activation, the clock and both
/// notification centres are stand-ins.
@MainActor
final class WindowPresenterTests: XCTestCase {
    private var isActive = true
    private var shown: [NSWindow] = []
    private var moved: [NSWindow] = []
    private var stranded: Set<ObjectIdentifier> = []
    private var activations = 0
    private var attentionRequests = 0
    private var timers: [(delay: TimeInterval, body: @MainActor () -> Void)] = []
    private var appNotifications: NotificationCenter!
    private var workspaceNotifications: NotificationCenter!
    private var policy: ActivationPolicyController!
    private var presenter: WindowPresenter!

    override func setUp() {
        super.setUp()
        isActive = true
        shown = []
        moved = []
        stranded = []
        activations = 0
        attentionRequests = 0
        timers = []
        appNotifications = NotificationCenter()
        workspaceNotifications = NotificationCenter()
        policy = ActivationPolicyController { _ in }
        presenter = makePresenter()
    }

    // MARK: - Showing

    func testAnotherWindowOfARegularActiveAppShowsAtOnce() {
        presenter.present(makeWindow())          // the app becomes regular
        spaceSwitched()
        let history = makeWindow()

        presenter.present(history)

        XCTAssertTrue(shown.last === history, "nothing is about to move Space")
    }

    /// The bug: clicked from the menu bar over a full-screen app, the
    /// Dashboard was put up before the switch to a desktop and stayed behind.
    func testTheFirstWindowWaitsForTheSwitchToADesktop() {
        let dashboard = makeWindow()

        presenter.present(dashboard)
        XCTAssertTrue(shown.isEmpty, "the Space is about to change")

        spaceSwitched()
        XCTAssertTrue(shown.first === dashboard)
        XCTAssertEqual(shown.count, 1)
    }

    /// Already on a desktop, no switch comes; the wait is bounded.
    func testOnADesktopTheFirstWindowShowsAfterTheSettleDelay() {
        let dashboard = makeWindow()
        presenter.present(dashboard)

        fireTimer(after: WindowPresenter.settleDelay)

        XCTAssertTrue(shown.first === dashboard)
    }

    func testTheSwitchAndTheSettleDelayTogetherShowTheWindowOnce() {
        presenter.present(makeWindow())

        spaceSwitched()
        fireTimer(after: WindowPresenter.settleDelay)

        XCTAssertEqual(shown.count, 1)
    }

    func testAskingAgainWhileItWaitsShowsTheWindowOnce() {
        let dashboard = makeWindow()
        presenter.present(dashboard)
        presenter.present(dashboard)

        spaceSwitched()

        XCTAssertEqual(shown.count, 1)
    }

    func testAWindowAskedForWhileAnotherWaitsShowsWithIt() {
        let welcome = makeWindow()
        let dashboard = makeWindow()
        presenter.present(welcome)
        presenter.present(dashboard)

        spaceSwitched()

        XCTAssertEqual(shown.count, 2)
    }

    /// "Dashboard" chosen from the menu in a full-screen app, the Dashboard
    /// already open on a desktop: AudioWhisper stepped aside to an accessory
    /// so the menu could open, and becoming regular again moves to a desktop.
    func testAWindowShownAfterTheMenuSteppedAsideWaitsForTheSwitch() {
        let dashboard = makeWindow()
        presenter.present(dashboard)
        spaceSwitched()
        policy.statusMenuWillOpen()

        presenter.present(dashboard)
        XCTAssertEqual(shown.count, 1, "the Space is about to change")

        spaceSwitched()
        XCTAssertEqual(shown.count, 2)
    }

    // MARK: - In the background

    /// Brought in from the background, a window lands on whatever Space is
    /// showing, full-screen included. It waits instead, and the Dock icon
    /// bounces if activation is refused.
    func testInTheBackgroundTheWindowWaitsForActivation() {
        isActive = false
        let dashboard = makeWindow()

        presenter.present(dashboard)
        XCTAssertEqual(activations, 1)
        XCTAssertTrue(shown.isEmpty)

        fireTimer(after: WindowPresenter.activationTimeout)
        XCTAssertEqual(attentionRequests, 1, "activation was refused: bounce the Dock icon")
        XCTAssertTrue(shown.isEmpty, "and still do not cover the user's Space")

        appBecameActive()
        XCTAssertTrue(shown.isEmpty, "activation may move to another Space too")
        spaceSwitched()
        XCTAssertTrue(shown.first === dashboard)
    }

    func testPromptActivationDoesNotBounceTheDockIcon() {
        isActive = false
        presenter.present(makeWindow())

        appBecameActive()
        fireTimer(after: WindowPresenter.activationTimeout)

        XCTAssertEqual(attentionRequests, 0)
    }

    func testASpaceSwitchBeforeActivationDoesNotShowTheWindow() {
        isActive = false
        presenter.present(makeWindow())

        spaceSwitched()

        XCTAssertTrue(shown.isEmpty)
    }

    // MARK: - A late switch

    func testAWindowLeftBehindByASlowSwitchFollowsIt() {
        let dashboard = makeWindow()
        presenter.present(dashboard)
        fireTimer(after: WindowPresenter.settleDelay)   // switch slower than the wait

        stranded.insert(ObjectIdentifier(dashboard))
        spaceSwitched()

        XCTAssertTrue(moved.first === dashboard)
    }

    func testAWindowOnTheNewSpaceAlreadyStaysPut() {
        presenter.present(makeWindow())
        fireTimer(after: WindowPresenter.settleDelay)

        spaceSwitched()

        XCTAssertTrue(moved.isEmpty)
    }

    /// Once the window has been up a while, a Space change is the user's
    /// doing; the window stays on its Space like any other.
    func testAfterAWhileTheWindowNoLongerFollowsSpaceChanges() {
        let dashboard = makeWindow()
        presenter.present(dashboard)
        fireTimer(after: WindowPresenter.settleDelay)
        fireTimer(after: WindowPresenter.lateSwitchWindow)

        stranded.insert(ObjectIdentifier(dashboard))
        spaceSwitched()

        XCTAssertTrue(moved.isEmpty)
    }

    // MARK: - Helpers

    private func makePresenter() -> WindowPresenter {
        let environment = WindowPresenter.Environment(
            isAppActive: { [unowned self] in isActive },
            activateApp: { [unowned self] in activations += 1 },
            requestAttention: { [unowned self] in attentionRequests += 1 },
            after: { [unowned self] delay, body in timers.append((delay, body)) },
            orderFront: { [unowned self] in shown.append($0) },
            isStranded: { [unowned self] in stranded.contains(ObjectIdentifier($0)) },
            moveToActiveSpace: { [unowned self] in moved.append($0) },
            appNotifications: appNotifications,
            workspaceNotifications: workspaceNotifications
        )
        return WindowPresenter(environment: environment, policy: policy)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                 styleMask: [.titled, .closable], backing: .buffered, defer: true)
    }

    private func spaceSwitched() {
        workspaceNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    }

    private func appBecameActive() {
        isActive = true
        appNotifications.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    /// Runs the earliest pending timer scheduled with `delay`.
    private func fireTimer(after delay: TimeInterval, file: StaticString = #filePath, line: UInt = #line) {
        guard let index = timers.firstIndex(where: { $0.delay == delay }) else {
            return XCTFail("no timer scheduled for \(delay)s", file: file, line: line)
        }
        timers.remove(at: index).body()
    }
}

/// The real AppKit side of `WindowPresenter`, on a borderless window far off
/// every screen, so nothing appears while the suite runs.
@MainActor
final class WindowPresenterLiveEnvironmentTests: XCTestCase {
    private let live = WindowPresenter.Environment.live
    private var window: NSWindow!

    override func setUp() {
        super.setUp()
        window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 10, height: 10),
                          styleMask: [.borderless], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
    }

    override func tearDown() {
        window.orderOut(nil)
        window = nil
        super.tearDown()
    }

    func testDelayedWorkRunsLaterOnTheMainQueue() {
        var ran = false
        let done = expectation(description: "ran")

        live.after(0) {
            ran = true
            done.fulfill()
        }

        XCTAssertFalse(ran, "it must not run before the caller has finished")
        wait(for: [done], timeout: 1)
    }

    func testOrderingFrontPutsTheWindowOnScreen() {
        live.orderFront(window)

        XCTAssertTrue(window.isVisible)
    }

    func testAWindowNotOnScreenIsNotStranded() {
        XCTAssertFalse(live.isStranded(window), "a closed window has no Space to be left behind on")
    }

    /// `.moveToActiveSpace` is only for the one move: kept, the window would
    /// jump to whichever Space is active each time AudioWhisper is.
    func testMovingAWindowToTheActiveSpaceDoesNotLeaveItFollowingSpaces() {
        let behavior = window.collectionBehavior
        let restored = expectation(description: "behaviour restored")

        live.moveToActiveSpace(window)
        DispatchQueue.main.async { restored.fulfill() }
        wait(for: [restored], timeout: 1)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.collectionBehavior, behavior)
    }
}
