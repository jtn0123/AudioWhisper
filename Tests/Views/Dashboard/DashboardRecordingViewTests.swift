import XCTest
@testable import AudioWhisper

final class DashboardRecordingViewTests: XCTestCase {

    // MARK: - Waveform Style Icons

    func testStyleIconForAllStyles() {
        XCTAssertEqual(DashboardRecordingView.testableStyleIcon(for: .classic), "waveform")
        XCTAssertEqual(DashboardRecordingView.testableStyleIcon(for: .neon), "sparkles")
        XCTAssertEqual(DashboardRecordingView.testableStyleIcon(for: .spectrum), "chart.bar.fill")
        XCTAssertEqual(DashboardRecordingView.testableStyleIcon(for: .circular), "sun.max.fill")
        XCTAssertEqual(DashboardRecordingView.testableStyleIcon(for: .pulseRings), "dot.radiowaves.left.and.right")
        XCTAssertEqual(DashboardRecordingView.testableStyleIcon(for: .particles), "sparkle")
    }

    func testAllStylesHaveUniqueIcons() {
        let icons = WaveformStyle.allCases.map { DashboardRecordingView.testableStyleIcon(for: $0) }
        let uniqueIcons = Set(icons)

        XCTAssertEqual(icons.count, uniqueIcons.count, "Each waveform style should have a unique icon")
    }

    // MARK: - Waveform Style Parsing

    func testWaveformStyleFromValidValues() {
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: "Classic"), .classic)
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: "Neon"), .neon)
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: "Spectrum"), .spectrum)
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: "Circular"), .circular)
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: "Pulse Rings"), .pulseRings)
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: "Particles"), .particles)
    }

    func testWaveformStyleFromInvalidValue() {
        // Should default to classic
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: "invalid"), .classic)
        XCTAssertEqual(DashboardRecordingView.testableWaveformStyle(from: ""), .classic)
    }

    // MARK: - Visual Intensity Parsing

    func testVisualIntensityFromValidValues() {
        for intensity in VisualIntensity.allCases {
            XCTAssertEqual(
                DashboardRecordingView.testableVisualIntensity(from: intensity.rawValue),
                intensity
            )
        }
    }

    func testVisualIntensityFromInvalidValue() {
        // Should default to balanced
        XCTAssertEqual(DashboardRecordingView.testableVisualIntensity(from: "invalid"), .balanced)
        XCTAssertEqual(DashboardRecordingView.testableVisualIntensity(from: ""), .balanced)
    }

    // MARK: - Press and Hold Mode Parsing

    func testPressAndHoldModeFromValidValues() {
        for mode in PressAndHoldMode.allCases {
            XCTAssertEqual(
                DashboardRecordingView.testablePressAndHoldMode(from: mode.rawValue),
                mode
            )
        }
    }

    func testPressAndHoldModeFromInvalidValue() {
        let defaultMode = PressAndHoldConfiguration.defaults.mode
        XCTAssertEqual(DashboardRecordingView.testablePressAndHoldMode(from: "invalid"), defaultMode)
        XCTAssertEqual(DashboardRecordingView.testablePressAndHoldMode(from: ""), defaultMode)
    }

    // MARK: - Press and Hold Key Parsing

    func testPressAndHoldKeyFromValidValues() {
        for key in PressAndHoldKey.allCases {
            XCTAssertEqual(
                DashboardRecordingView.testablePressAndHoldKey(from: key.rawValue),
                key
            )
        }
    }

    func testPressAndHoldKeyFromInvalidValue() {
        let defaultKey = PressAndHoldConfiguration.defaults.key
        XCTAssertEqual(DashboardRecordingView.testablePressAndHoldKey(from: "invalid"), defaultKey)
        XCTAssertEqual(DashboardRecordingView.testablePressAndHoldKey(from: ""), defaultKey)
    }

    // MARK: - Waveform Style Properties

    func testAllWaveformStylesHaveDescriptions() {
        for style in WaveformStyle.allCases {
            XCTAssertFalse(style.description.isEmpty, "Waveform style \(style) should have a description")
        }
    }

    // MARK: - Visual Intensity Properties

    func testAllVisualIntensitiesHaveIcons() {
        for intensity in VisualIntensity.allCases {
            XCTAssertFalse(intensity.icon.isEmpty, "Visual intensity \(intensity) should have an icon")
        }
    }

    func testAllVisualIntensitiesHaveDescriptions() {
        for intensity in VisualIntensity.allCases {
            XCTAssertFalse(intensity.description.isEmpty, "Visual intensity \(intensity) should have a description")
        }
    }

    // MARK: - Press and Hold Properties

    func testAllPressAndHoldModesHaveDisplayNames() {
        for mode in PressAndHoldMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "Press and hold mode \(mode) should have a display name")
        }
    }

    func testAllPressAndHoldKeysHaveDisplayNames() {
        for key in PressAndHoldKey.allCases {
            XCTAssertFalse(key.displayName.isEmpty, "Press and hold key \(key) should have a display name")
        }
    }
}
