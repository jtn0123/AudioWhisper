import XCTest
@testable import AudioWhisper

final class DashboardVisualsViewTests: XCTestCase {

    // MARK: - Waveform Style Parsing

    func testWaveformStyleFromValidValues() {
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Classic"), .classic)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Neon"), .neon)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Spectrum"), .spectrum)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Stream"), .stream)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Constellation"), .constellation)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Halo"), .halo)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Dial"), .dial)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Heartbeat"), .heartbeat)
    }

    func testWaveformStyleFromAllRawValuesRoundTrips() {
        for style in WaveformStyle.allCases {
            XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: style.rawValue), style)
        }
    }

    func testWaveformStyleFromInvalidValue() {
        // Should default to classic
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "invalid"), .classic)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: ""), .classic)
        // Legacy raw values are no longer recognized and fall back to classic.
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Circular"), .classic)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Pulse Rings"), .classic)
        XCTAssertEqual(DashboardVisualsView.testableWaveformStyle(from: "Particles"), .classic)
    }

    // MARK: - Visual Intensity Parsing

    func testVisualIntensityFromValidValues() {
        for intensity in VisualIntensity.allCases {
            XCTAssertEqual(
                DashboardVisualsView.testableVisualIntensity(from: intensity.rawValue),
                intensity
            )
        }
    }

    func testVisualIntensityFromInvalidValue() {
        // Should default to balanced
        XCTAssertEqual(DashboardVisualsView.testableVisualIntensity(from: "invalid"), .balanced)
        XCTAssertEqual(DashboardVisualsView.testableVisualIntensity(from: ""), .balanced)
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
}
