import XCTest
@testable import AudioWhisper

// MARK: - AppDefaults Extension Accessor Coverage
//
// Exercises accessors across AppDefaults+Settings / +Visual / +FeatureFlags
// that are not already covered by AppDefaultsTests, restoring each key after.
@MainActor
final class AppDefaultsExtensionsCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): AppDefaults reads/writes UserDefaults.standard directly.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var originalValues: [String: Any?] = [:]
    private let touchedKeys: [AppDefaults.Key] = [
        .pressAndHoldEnabled, .pressAndHoldKeyIdentifier, .pressAndHoldMode,
        .autoBoostMicrophoneVolume, .enableSmartPaste, .playCompletionSound,
        .startAtLogin, .hasSetupParakeet, .hasSetupLocalLLM,
        .hasCompletedWelcome, .lastWelcomeVersion, .hasShownFirstModelUseHint,
        .hasCleanedWindowState, .waveformStyle, .visualIntensity,
        .menuBarIconSize, .semanticCorrectionModelRepo, .maxModelStorageGB
    ]

    override func setUp() {
        super.setUp()
        for key in touchedKeys {
            originalValues[key.rawValue] = UserDefaults.standard.object(forKey: key.rawValue)
        }
    }

    override func tearDown() {
        for (rawKey, value) in originalValues {
            if let value = value {
                UserDefaults.standard.set(value, forKey: rawKey)
            } else {
                UserDefaults.standard.removeObject(forKey: rawKey)
            }
        }
        originalValues.removeAll()
        super.tearDown()
    }

    // MARK: - Settings

    func testPressAndHoldEnabledRoundTrip() {
        AppDefaults.pressAndHoldEnabled = true
        XCTAssertTrue(AppDefaults.pressAndHoldEnabled)
        AppDefaults.pressAndHoldEnabled = false
        XCTAssertFalse(AppDefaults.pressAndHoldEnabled)
    }

    func testPressAndHoldEnabledDefaultWhenUnset() {
        AppDefaults.removeValue(for: .pressAndHoldEnabled)
        XCTAssertEqual(AppDefaults.pressAndHoldEnabled, PressAndHoldConfiguration.defaults.enabled)
    }

    func testPressAndHoldKeyIdentifierRoundTrip() {
        AppDefaults.pressAndHoldKeyIdentifier = "rightOption"
        XCTAssertEqual(AppDefaults.pressAndHoldKeyIdentifier, "rightOption")
    }

    func testPressAndHoldKeyIdentifierDefaultWhenUnset() {
        AppDefaults.removeValue(for: .pressAndHoldKeyIdentifier)
        XCTAssertEqual(AppDefaults.pressAndHoldKeyIdentifier, PressAndHoldConfiguration.defaults.key.rawValue)
    }

    func testPressAndHoldModeRoundTrip() {
        AppDefaults.pressAndHoldMode = "pushToTalk"
        XCTAssertEqual(AppDefaults.pressAndHoldMode, "pushToTalk")
    }

    func testPressAndHoldModeDefaultWhenUnset() {
        AppDefaults.removeValue(for: .pressAndHoldMode)
        XCTAssertEqual(AppDefaults.pressAndHoldMode, PressAndHoldConfiguration.defaults.mode.rawValue)
    }

    func testAutoBoostMicrophoneVolumeRoundTrip() {
        AppDefaults.autoBoostMicrophoneVolume = true
        XCTAssertTrue(AppDefaults.autoBoostMicrophoneVolume)
        AppDefaults.autoBoostMicrophoneVolume = false
        XCTAssertFalse(AppDefaults.autoBoostMicrophoneVolume)
    }

    func testEnableSmartPasteRoundTripAndDefault() {
        AppDefaults.removeValue(for: .enableSmartPaste)
        XCTAssertTrue(AppDefaults.enableSmartPaste)
        AppDefaults.enableSmartPaste = false
        XCTAssertFalse(AppDefaults.enableSmartPaste)
    }

    func testPlayCompletionSoundRoundTrip() {
        AppDefaults.playCompletionSound = false
        XCTAssertFalse(AppDefaults.playCompletionSound)
        AppDefaults.playCompletionSound = true
        XCTAssertTrue(AppDefaults.playCompletionSound)
    }

    func testStartAtLoginRoundTrip() {
        AppDefaults.startAtLogin = false
        XCTAssertFalse(AppDefaults.startAtLogin)
        AppDefaults.startAtLogin = true
        XCTAssertTrue(AppDefaults.startAtLogin)
    }

    func testSemanticCorrectionModelRepoDefaultWhenUnset() {
        // Assert the WIRING (getter falls back to the documented default)
        // rather than duplicating the literal — AppDefaultsTests pins the value.
        AppDefaults.removeValue(for: .semanticCorrectionModelRepo)
        XCTAssertEqual(
            AppDefaults.semanticCorrectionModelRepo,
            AppDefaults.defaultSemanticCorrectionModelRepo
        )
    }

    func testMaxModelStorageGBRoundTrip() {
        AppDefaults.maxModelStorageGB = 12.5
        XCTAssertEqual(AppDefaults.maxModelStorageGB, 12.5)
    }

    // MARK: - Visual

    func testWaveformStyleRoundTrip() {
        for style in WaveformStyle.allCases {
            AppDefaults.waveformStyle = style
            XCTAssertEqual(AppDefaults.waveformStyle, style)
        }
    }

    func testWaveformStyleDefaultWhenUnset() {
        AppDefaults.removeValue(for: .waveformStyle)
        XCTAssertEqual(AppDefaults.waveformStyle, .classic)
    }

    func testWaveformStyleInvalidValueFallsBack() {
        UserDefaults.standard.set("not-a-style", forKey: AppDefaults.Key.waveformStyle.rawValue)
        XCTAssertEqual(AppDefaults.waveformStyle, .classic)
    }

    func testVisualIntensityInvalidValueFallsBack() {
        UserDefaults.standard.set("bogus", forKey: AppDefaults.Key.visualIntensity.rawValue)
        XCTAssertEqual(AppDefaults.visualIntensity, .balanced)
    }

    func testMenuBarIconSizeRoundTripAndClear() {
        AppDefaults.menuBarIconSize = 22.0
        XCTAssertEqual(AppDefaults.menuBarIconSize, 22.0)
        AppDefaults.menuBarIconSize = nil
        XCTAssertNil(AppDefaults.menuBarIconSize)
        XCTAssertFalse(AppDefaults.hasValue(for: .menuBarIconSize))
    }

    // MARK: - Feature Flags

    func testSetupStateFlagsRoundTrip() {
        AppDefaults.hasSetupParakeet = true
        AppDefaults.hasSetupLocalLLM = true
        AppDefaults.hasCompletedWelcome = true
        AppDefaults.hasShownFirstModelUseHint = true
        AppDefaults.hasCleanedWindowState = true
        XCTAssertTrue(AppDefaults.hasSetupParakeet)
        XCTAssertTrue(AppDefaults.hasSetupLocalLLM)
        XCTAssertTrue(AppDefaults.hasCompletedWelcome)
        XCTAssertTrue(AppDefaults.hasShownFirstModelUseHint)
        XCTAssertTrue(AppDefaults.hasCleanedWindowState)
    }

    func testHasCleanedWindowStateDefaultWhenUnset() {
        AppDefaults.removeValue(for: .hasCleanedWindowState)
        XCTAssertFalse(AppDefaults.hasCleanedWindowState)
    }

    func testLastWelcomeVersionRoundTripAndDefault() {
        AppDefaults.removeValue(for: .lastWelcomeVersion)
        XCTAssertEqual(AppDefaults.lastWelcomeVersion, "0")
        AppDefaults.lastWelcomeVersion = "1.1"
        XCTAssertEqual(AppDefaults.lastWelcomeVersion, "1.1")
    }
}
