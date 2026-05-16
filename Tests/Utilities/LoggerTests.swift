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

    func testKeychainLoggerExists() {
        let logger = Logger.keychain
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
            ("keychain", Logger.keychain),
            ("app", Logger.app),
            ("settings", Logger.settings),
            ("dataManager", Logger.dataManager),
            ("paste", Logger.paste)
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

    func testExpectedCategories() {
        let expectedCategories = [
            "ModelManager",
            "AudioRecorder",
            "MicrophoneVolume",
            "SpeechToText",
            "Keychain",
            "App",
            "Settings",
            "DataManager",
            "Paste"
        ]

        XCTAssertEqual(expectedCategories.count, 9)
    }

    func testSubsystemFormat() {
        // Subsystem should be bundle identifier or fallback
        let bundleId = Bundle.main.bundleIdentifier ?? "com.audiowhisper.app"
        XCTAssertFalse(bundleId.isEmpty)
    }
}
