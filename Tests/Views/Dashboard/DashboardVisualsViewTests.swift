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

    // MARK: - Mic Test Banner / Sampler Mic Mode

    @MainActor
    func testMicTestBannerConstructs() {
        let sampler = LivePreviewSampler()
        let capture = MicTestCapture(sampler: sampler)
        _ = MicTestBanner(style: .classic, sampler: sampler, capture: capture)
        XCTAssertEqual(capture.state, .off)
    }

    @MainActor
    func testSamplerMicModeTogglesAndResetsOnDisable() {
        let sampler = LivePreviewSampler()
        XCTAssertFalse(sampler.isMicMode)

        sampler.setMicMode(true)
        XCTAssertTrue(sampler.isMicMode)

        // Real mic frames drive the published values while mic mode is on.
        sampler.publishMicFrame(level: 0.8, samples: [0.5, -0.5], bands: [0.3, 0.6])
        XCTAssertEqual(sampler.audioLevel, 0.8, accuracy: 0.0001)
        XCTAssertEqual(sampler.samples.count, 2)
        XCTAssertEqual(sampler.bands.count, 2)

        // Disabling mic mode restores the idle defaults.
        sampler.setMicMode(false)
        XCTAssertFalse(sampler.isMicMode)
        XCTAssertEqual(sampler.audioLevel, 0.2, accuracy: 0.0001)
        XCTAssertTrue(sampler.samples.isEmpty)
        XCTAssertTrue(sampler.bands.isEmpty)
    }

    @MainActor
    func testSamplerIgnoresMicFrameWhenMicModeOff() {
        let sampler = LivePreviewSampler()
        sampler.publishMicFrame(level: 0.9, samples: [1], bands: [1])
        // Mic mode is off — frame is ignored, idle default preserved.
        XCTAssertEqual(sampler.audioLevel, 0.2, accuracy: 0.0001)
    }

    @MainActor
    func testMicCaptureStopReturnsToOffState() {
        let sampler = LivePreviewSampler()
        let capture = MicTestCapture(sampler: sampler)
        capture.stop()
        XCTAssertEqual(capture.state, .off)
        XCTAssertEqual(capture.level, 0, accuracy: 0.0001)
        XCTAssertFalse(capture.speaking)
    }
}
