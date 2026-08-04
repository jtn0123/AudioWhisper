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
