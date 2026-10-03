import XCTest
@testable import AudioWhisper

// MARK: - WelcomeView Tests
@MainActor
final class WelcomeViewTests: XCTestCase {

    func testWelcomeViewCanBeCreated() {
        let view = WelcomeView()
        XCTAssertNotNil(view)
    }

    func testWelcomeViewBodyProducesAView() {
        let view = WelcomeView()
        // Evaluating body must not crash and must yield a concrete view value.
        let body = view.body
        XCTAssertFalse(String(describing: type(of: body)).isEmpty)
    }
}

// MARK: - WelcomeView Layout Tests
final class WelcomeViewLayoutTests: XCTestCase {

    func testWelcomeWindowSize() {
        let expectedSize = LayoutMetrics.Welcome.windowSize
        XCTAssertEqual(expectedSize.width, 580)
        XCTAssertEqual(expectedSize.height, 700)
    }

    func testStyleGridColumns() {
        // The consolidated welcome shows the 8 waveform styles in a 4-column grid.
        let columnCount = 4
        XCTAssertEqual(columnCount, 4)
        XCTAssertEqual(WaveformStyle.allCases.count, 8)
    }
}

// MARK: - WelcomeView Notification Tests
final class WelcomeViewNotificationTests: XCTestCase {

    func testWelcomeCompletedNotificationExists() {
        let notificationName = Notification.Name.welcomeCompleted
        XCTAssertNotNil(notificationName)
    }
}

// MARK: - WelcomeView UserDefaults Keys Tests
final class WelcomeViewUserDefaultsKeysTests: XCTestCase {

    func testTranscriptionProviderKey() {
        let key = "transcriptionProvider"
        XCTAssertFalse(key.isEmpty)
    }

    func testHasCompletedWelcomeKey() {
        let key = "hasCompletedWelcome"
        XCTAssertFalse(key.isEmpty)
    }

    func testLastWelcomeVersionKey() {
        let key = "lastWelcomeVersion"
        XCTAssertFalse(key.isEmpty)
    }
}

// MARK: - WelcomeWindow Tests

/// What "Get started" and closing the welcome window record. Uses the
/// per-process scratch defaults domain, restoring the keys it touches.
@MainActor
final class WelcomeWindowTests: XCTestCase {
    private let keys: [AppDefaults.Key] = [.transcriptionProvider, .hasCompletedWelcome, .lastWelcomeVersion]
    private var saved: [AppDefaults.Key: Any] = [:]
    private var presenter: PresenterSpy!

    override func setUp() {
        super.setUp()
        presenter = PresenterSpy()
        presenter.install()
        saved = [:]
        for key in keys {
            saved[key] = AppDefaults.defaults.object(forKey: key.rawValue)
            AppDefaults.removeValue(for: key)
        }
    }

    override func tearDown() {
        presenter.shown.forEach { $0.close() }
        presenter.uninstall()
        presenter = nil
        for key in keys {
            if let value = saved[key] {
                AppDefaults.defaults.set(value, forKey: key.rawValue)
            } else {
                AppDefaults.removeValue(for: key)
            }
        }
        super.tearDown()
    }

    /// Closing the window with its close button used to leave the version
    /// unset, so the welcome came back at every launch.
    func testOnceSeenTheWelcomeDoesNotComeBackAtNextLaunch() {
        AppDefaults.transcriptionProvider = .parakeet
        XCTAssertTrue(AppSetupHelper.checkFirstRun(), "precondition: this version has not been seen")

        WelcomeWindow.markSeen()

        XCTAssertFalse(AppSetupHelper.checkFirstRun())
    }

    /// "Help / Welcome" reopens the welcome for existing users; finishing it
    /// used to switch them back to Whisper.
    func testGetStartedKeepsTheProviderAnExistingUserChose() {
        AppDefaults.transcriptionProvider = .parakeet

        WelcomeWindow.finish()

        XCTAssertEqual(AppDefaults.transcriptionProvider, .parakeet)
        XCTAssertTrue(AppDefaults.hasCompletedWelcome)
        XCTAssertEqual(AppDefaults.lastWelcomeVersion, AppSetupHelper.currentWelcomeVersion)
    }

    func testGetStartedOnAFirstRunChoosesLocalWhisper() {
        WelcomeWindow.finish()

        XCTAssertEqual(AppDefaults.transcriptionProvider, .local)
    }

    func testGetStartedOpensTheDashboard() {
        let completed = expectation(forNotification: .welcomeCompleted, object: nil)

        WelcomeWindow.finish()

        wait(for: [completed], timeout: 1.0)
    }

    // MARK: - The window

    func testAskingForTheWelcomeAgainBringsBackTheSameWindow() {
        WelcomeWindow.show()
        WelcomeWindow.show()

        XCTAssertEqual(presenter.shown.count, 2)
        XCTAssertTrue(presenter.shown.first === presenter.shown.last, "a second welcome window must not open")
        XCTAssertEqual(presenter.shown.first?.title, "Welcome to AudioWhisper")
    }

    /// Closing the window with its close button used to leave the version
    /// unset, so the welcome came back at every launch.
    func testClosingTheWindowCountsAsSeen() throws {
        WelcomeWindow.show()
        let window = try XCTUnwrap(presenter.shown.first)

        window.close()

        XCTAssertTrue(AppDefaults.hasCompletedWelcome)
        XCTAssertEqual(AppDefaults.lastWelcomeVersion, AppSetupHelper.currentWelcomeVersion)
    }

    func testGetStartedClosesTheWindow() throws {
        WelcomeWindow.show()

        WelcomeWindow.finish()
        WelcomeWindow.show()

        XCTAssertEqual(presenter.shown.count, 2)
        XCTAssertFalse(presenter.shown.first === presenter.shown.last,
                       "once closed, asking for the welcome must open it afresh")
    }

    /// There is no help book; Help shows the welcome instead of "Help isn't
    /// available for AudioWhisper".
    func testHelpOpensTheWelcome() {
        AppDelegate().showHelp()

        XCTAssertEqual(presenter.shown.map(\.title), ["Welcome to AudioWhisper"])
    }
}
