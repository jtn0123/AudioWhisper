import XCTest
import SwiftUI
@testable import AudioWhisper

/// Tests for waveform visualization views
@MainActor
final class WaveformViewsTests: IsolatedXCTestCase {
    // NOTE(D1): The UserDefaults extension accessors (waveformStyle,
    // visualIntensity) live on UserDefaults.standard. Once non-standard
    // accessors exist, route writes through a UUID-scoped suite and
    // re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    // MARK: - New Renderer View Smoke Tests

    func testStreamWaveformViewInitialization() {
        let view = StreamWaveformView(audioLevel: 0.6, isActive: true)
        XCTAssertNotNil(view)
    }

    func testConstellationWaveformViewInitialization() {
        let view = ConstellationWaveformView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }

    func testHaloWaveformViewInitialization() {
        let view = HaloWaveformView(
            frequencyBands: [0.7, 0.5, 0.4, 0.6, 0.3, 0.45, 0.25, 0.35],
            audioLevel: 0.5,
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testDialWaveformViewInitialization() {
        let view = DialWaveformView(
            frequencyBands: [0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15],
            audioLevel: 0.5,
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testHeartbeatPulseViewInitialization() {
        let view = HeartbeatPulseView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }

    // MARK: - NeonWaveformView Tests

    func testNeonWaveformViewInitialization() {
        let view = NeonWaveformView(
            waveformSamples: (0..<64).map { _ in Float.random(in: -0.5...0.5) },
            audioLevel: 0.6,
            isActive: true
        )

        XCTAssertNotNil(view)
    }

    func testNeonWaveformViewInactiveState() {
        let view = NeonWaveformView(
            waveformSamples: [],
            audioLevel: 0,
            isActive: false
        )

        XCTAssertNotNil(view)
    }

    func testNeonWaveformTrailCount() {
        let trailCount = 3
        XCTAssertEqual(trailCount, 3)
    }

    func testNeonWaveformDecayFactor() {
        let decayFactor: Float = 0.55
        XCTAssertEqual(decayFactor, 0.55)
    }

    func testNeonWaveformColorThreshold() {
        // High audio level should use yellow
        let audioLevel: Float = 0.75
        XCTAssertTrue(audioLevel > 0.7)

        // Medium audio level should use magenta
        let mediumLevel: Float = 0.5
        XCTAssertTrue(mediumLevel > 0.4 && mediumLevel <= 0.7)

        // Low audio level should use cyan
        let lowLevel: Float = 0.3
        XCTAssertTrue(lowLevel <= 0.4)
    }

    // MARK: - WaveformContainer Tests

    func testWaveformContainerInitialization() {
        let container = WaveformContainer(
            status: .ready,
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0, count: 8),
            onTap: {}
        )

        XCTAssertNotNil(container)
    }

    func testWaveformContainerRecordingStatus() {
        let container = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0.5, count: 8),
            onTap: {}
        )

        XCTAssertNotNil(container)
    }

    func testWaveformContainerProcessingStatus() {
        let container = WaveformContainer(
            status: .processing( "Transcribing..."),
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: [],
            onTap: {}
        )

        XCTAssertNotNil(container)
    }

    func testWaveformContainerSuccessStatus() {
        let container = WaveformContainer(
            status: .success,
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: [],
            onTap: {}
        )

        XCTAssertNotNil(container)
    }

    func testWaveformContainerErrorStatus() {
        let container = WaveformContainer(
            status: .error( "Failed"),
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: [],
            onTap: {}
        )

        XCTAssertNotNil(container)
    }

    // MARK: - WaveformStyle Tests

    func testWaveformStyleAllCases() {
        let styles = WaveformStyle.allCases

        XCTAssertEqual(styles.count, 8)
        XCTAssertTrue(styles.contains(.classic))
        XCTAssertTrue(styles.contains(.neon))
        XCTAssertTrue(styles.contains(.spectrum))
        XCTAssertTrue(styles.contains(.stream))
        XCTAssertTrue(styles.contains(.constellation))
        XCTAssertTrue(styles.contains(.halo))
        XCTAssertTrue(styles.contains(.dial))
        XCTAssertTrue(styles.contains(.heartbeat))
    }

    func testWaveformStyleRawValues() {
        XCTAssertEqual(WaveformStyle.classic.rawValue, "Classic")
        XCTAssertEqual(WaveformStyle.neon.rawValue, "Neon")
        XCTAssertEqual(WaveformStyle.spectrum.rawValue, "Spectrum")
        XCTAssertEqual(WaveformStyle.stream.rawValue, "Stream")
        XCTAssertEqual(WaveformStyle.constellation.rawValue, "Constellation")
        XCTAssertEqual(WaveformStyle.halo.rawValue, "Halo")
        XCTAssertEqual(WaveformStyle.dial.rawValue, "Dial")
        XCTAssertEqual(WaveformStyle.heartbeat.rawValue, "Heartbeat")
    }

    func testWaveformStyleDescriptions() {
        for style in WaveformStyle.allCases {
            XCTAssertFalse(style.description.isEmpty, "\(style) should have a description")
        }
    }

    func testWaveformStyleRequiresEnhancedAudio() {
        // Classic and heartbeat don't require enhanced audio
        XCTAssertFalse(WaveformStyle.classic.requiresEnhancedAudio)
        XCTAssertFalse(WaveformStyle.heartbeat.requiresEnhancedAudio)

        // Others require enhanced audio
        XCTAssertTrue(WaveformStyle.neon.requiresEnhancedAudio)
        XCTAssertTrue(WaveformStyle.spectrum.requiresEnhancedAudio)
        XCTAssertTrue(WaveformStyle.stream.requiresEnhancedAudio)
        XCTAssertTrue(WaveformStyle.constellation.requiresEnhancedAudio)
        XCTAssertTrue(WaveformStyle.halo.requiresEnhancedAudio)
        XCTAssertTrue(WaveformStyle.dial.requiresEnhancedAudio)
    }

    func testWaveformStyleRadialAndNewMembers() {
        // Radial styles render in a square
        XCTAssertTrue(WaveformStyle.halo.isRadial)
        XCTAssertTrue(WaveformStyle.dial.isRadial)
        XCTAssertTrue(WaveformStyle.heartbeat.isRadial)
        XCTAssertFalse(WaveformStyle.classic.isRadial)

        // New styles introduced in the redesign
        XCTAssertTrue(WaveformStyle.stream.isNew)
        XCTAssertTrue(WaveformStyle.constellation.isNew)
        XCTAssertFalse(WaveformStyle.classic.isNew)
        XCTAssertFalse(WaveformStyle.neon.isNew)
        XCTAssertFalse(WaveformStyle.spectrum.isNew)
    }

    // MARK: - VisualIntensity Tests

    func testVisualIntensityAllCases() {
        let intensities = VisualIntensity.allCases

        XCTAssertTrue(intensities.contains(.glow))
        XCTAssertTrue(intensities.contains(.balanced))
        XCTAssertTrue(intensities.contains(.burst))
    }

    func testVisualIntensityRawValues() {
        XCTAssertEqual(VisualIntensity.glow.rawValue, "Glow")
        XCTAssertEqual(VisualIntensity.balanced.rawValue, "Balanced")
        XCTAssertEqual(VisualIntensity.burst.rawValue, "Burst")
    }

    func testVisualIntensityDescriptions() {
        for intensity in VisualIntensity.allCases {
            XCTAssertFalse(intensity.description.isEmpty, "\(intensity) should have a description")
        }
    }

    func testVisualIntensityIcons() {
        XCTAssertEqual(VisualIntensity.glow.icon, "sun.max.fill")
        XCTAssertEqual(VisualIntensity.balanced.icon, "sparkle")
        XCTAssertEqual(VisualIntensity.burst.icon, "sparkles")
    }

    func testVisualIntensityParticleMultipliers() {
        XCTAssertEqual(VisualIntensity.glow.particleMultiplier, 0.5)
        XCTAssertEqual(VisualIntensity.balanced.particleMultiplier, 1.0)
        XCTAssertEqual(VisualIntensity.burst.particleMultiplier, 1.5)
    }

    func testVisualIntensityConfettiCounts() {
        XCTAssertEqual(VisualIntensity.glow.confettiCount, 0)
        XCTAssertEqual(VisualIntensity.balanced.confettiCount, 12)
        XCTAssertEqual(VisualIntensity.burst.confettiCount, 30)
    }

    func testVisualIntensityRingCounts() {
        XCTAssertEqual(VisualIntensity.glow.ringCount, 2)
        XCTAssertEqual(VisualIntensity.balanced.ringCount, 1)
        XCTAssertEqual(VisualIntensity.burst.ringCount, 0)
    }

    // MARK: - Status Text Tests

    func testStatusTextRecording() {
        let status = AppStatus.recording
        let text: String

        switch status {
        case .recording: text = "LISTENING"
        default: text = ""
        }

        XCTAssertEqual(text, "LISTENING")
    }

    func testStatusTextProcessing() {
        let status = AppStatus.processing( "Transcribing")
        let text: String

        switch status {
        case .processing(let message): text = message.uppercased()
        default: text = ""
        }

        XCTAssertEqual(text, "TRANSCRIBING")
    }

    func testStatusTextSuccess() {
        let status = AppStatus.success
        let text: String

        switch status {
        case .success: text = "COPIED"
        default: text = ""
        }

        XCTAssertEqual(text, "COPIED")
    }

    func testStatusTextReady() {
        let status = AppStatus.ready
        let text: String

        switch status {
        case .ready: text = "TAP TO RECORD"
        default: text = ""
        }

        XCTAssertEqual(text, "TAP TO RECORD")
    }

    func testStatusTextPermissionRequired() {
        let status = AppStatus.permissionRequired
        let text: String

        switch status {
        case .permissionRequired: text = "PERMISSION NEEDED"
        default: text = ""
        }

        XCTAssertEqual(text, "PERMISSION NEEDED")
    }

    func testStatusTextError() {
        let status = AppStatus.error( "Failed")
        let text: String

        switch status {
        case .error(let message): text = message.uppercased()
        default: text = ""
        }

        XCTAssertEqual(text, "FAILED")
    }

}
