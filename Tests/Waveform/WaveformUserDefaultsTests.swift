import XCTest
import SwiftUI
@testable import AudioWhisper

/// Tests for the waveform-related `UserDefaults` extension accessors. Split
/// out of `WaveformViewsTests` to keep each test class within the type body
/// length budget.
@MainActor
final class WaveformUserDefaultsTests: IsolatedXCTestCase {
    // NOTE(D1): The UserDefaults extension accessors (waveformStyle,
    // visualIntensity) live on UserDefaults.standard. Once non-standard
    // accessors exist, route writes through a UUID-scoped suite and
    // re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    func testUserDefaultsWaveformStyleKey() {
        let defaults = AppDefaults.defaults
        let key = "waveformStyle"

        defaults.removeObject(forKey: key)
        XCTAssertEqual(defaults.waveformStyle, .classic, "Default should be .classic")

        defaults.waveformStyle = .neon
        XCTAssertEqual(defaults.waveformStyle, .neon)

        // Cleanup
        defaults.removeObject(forKey: key)
    }

    func testUserDefaultsVisualIntensityKey() {
        let defaults = AppDefaults.defaults
        let key = "visualIntensity"

        defaults.removeObject(forKey: key)
        XCTAssertEqual(defaults.visualIntensity, .balanced, "Default should be .balanced")

        defaults.visualIntensity = .burst
        XCTAssertEqual(defaults.visualIntensity, .burst)

        // Cleanup
        defaults.removeObject(forKey: key)
    }
}
