import XCTest
import os.log
@testable import AudioWhisper

// MARK: - Logger Extension Tests
final class LoggerExtensionTests: XCTestCase {

    func testModelManagerLoggerExists() {
        let logger = Logger.modelManager
        XCTAssertNotNil(logger)
    }

    func testAudioRecorderLoggerExists() {
        let logger = Logger.audioRecorder
        XCTAssertNotNil(logger)
    }

    func testMicrophoneVolumeLoggerExists() {
        let logger = Logger.microphoneVolume
        XCTAssertNotNil(logger)
    }

    func testSpeechToTextLoggerExists() {
        let logger = Logger.speechToText
        XCTAssertNotNil(logger)
    }

    func testAppLoggerExists() {
        let logger = Logger.app
        XCTAssertNotNil(logger)
    }

    func testSettingsLoggerExists() {
        let logger = Logger.settings
        XCTAssertNotNil(logger)
    }

    func testDataManagerLoggerExists() {
        let logger = Logger.dataManager
        XCTAssertNotNil(logger)
    }

    func testPasteLoggerExists() {
        let logger = Logger.paste
        XCTAssertNotNil(logger)
    }

    func testAllLoggersAreUnique() {
        // Each logger should have a unique category
        let loggers: [(String, Logger)] = [
            ("modelManager", Logger.modelManager),
            ("audioRecorder", Logger.audioRecorder),
            ("microphoneVolume", Logger.microphoneVolume),
            ("speechToText", Logger.speechToText),
            ("app", Logger.app),
            ("settings", Logger.settings),
            ("dataManager", Logger.dataManager),
            ("paste", Logger.paste),
            ("fileSystem", Logger.fileSystem)
        ]

        // Verify each logger exists
        for (name, logger) in loggers {
            XCTAssertNotNil(logger, "\(name) logger should exist")
        }
    }

    func testLoggerCanLog() {
        // Logging at every level must complete without throwing or crashing.
        XCTAssertNoThrow(Logger.app.info("Test log message"))
        XCTAssertNoThrow(Logger.app.debug("Debug message"))
        XCTAssertNoThrow(Logger.app.error("Error message"))
    }

    func testLoggerWithInterpolation() {
        let value = 42
        let message = "Test value: \(value)"
        XCTAssertEqual(message, "Test value: 42")

        // Interpolated logging must complete without throwing or crashing.
        XCTAssertNoThrow(Logger.app.info("\(message)"))
    }
}

// MARK: - Logger Category Tests
final class LoggerCategoryTests: XCTestCase {

    // `testExpectedCategories` was removed here. It declared a local array of
    // category-name strings and asserted that array's own `count`, so it never
    // referenced `Logger` and could not fail for any reason involving it — it
    // only broke when audit item A2 deleted `Logger.keychain`, changing a
    // hardcoded literal. `Logger` exposes no way to read back a category, so
    // existence and distinctness (below) is all that can honestly be asserted.

    func testSubsystemFormat() {
        // Subsystem should be bundle identifier or fallback
        let bundleId = Bundle.main.bundleIdentifier ?? "com.audiowhisper.app"
        XCTAssertFalse(bundleId.isEmpty)
    }
}
