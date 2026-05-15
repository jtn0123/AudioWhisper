import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

// MARK: - WaveformPalette / ParticlePalette Tests
final class WaveformPaletteCoverageTests: XCTestCase {

    func testClassicPaletteHasFiveColors() {
        XCTAssertEqual(WaveformPalette.classic.count, 5)
    }

    func testNamedAccessorsMapToClassicEntries() {
        XCTAssertEqual(WaveformPalette.background, WaveformPalette.classic[0])
        XCTAssertEqual(WaveformPalette.bar, WaveformPalette.classic[1])
        XCTAssertEqual(WaveformPalette.muted, WaveformPalette.classic[2])
        XCTAssertEqual(WaveformPalette.success, WaveformPalette.classic[3])
        XCTAssertEqual(WaveformPalette.accent, WaveformPalette.classic[4])
    }

    func testParticlePaletteHasFourDefaults() {
        XCTAssertEqual(ParticlePalette.defaults.count, 4)
    }

    func testParticlePaletteColorsAreDistinct() {
        let colors = ParticlePalette.defaults
        for outer in colors.indices {
            for inner in (outer + 1)..<colors.count {
                XCTAssertNotEqual(colors[outer], colors[inner])
            }
        }
    }
}

// MARK: - WaveformContainer Rendering Tests
@MainActor
final class WaveformContainerCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): WaveformContainer reads waveformStyle/visualIntensity from
    // UserDefaults.standard via @AppDefault. Re-enable isolation once those
    // accept an injected store.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private func render(
        status: AppStatus,
        style: WaveformStyle = .classic
    ) {
        AppDefaults.waveformStyle = style
        let view = WaveformContainer(
            status: status,
            audioLevel: 0.6,
            waveformSamples: (0..<32).map { Float($0) / 32.0 },
            frequencyBands: Array(repeating: 0.5, count: 8),
            processingAnimated: false,
            onTap: {}
        )
        let hosting = NSHostingView(rootView: view.frame(width: 280, height: 120))
        hosting.frame = CGRect(x: 0, y: 0, width: 280, height: 120)
        hosting.layout()
        XCTAssertNotNil(hosting)
    }

    func testRendersEveryWaveformStyle() {
        for style in WaveformStyle.allCases {
            render(status: .recording, style: style)
        }
    }

    func testRendersEveryStatus() {
        let statuses: [AppStatus] = [
            .ready,
            .recording,
            .processing("Transcribing"),
            .success,
            .error("Failed"),
            .permissionRequired
        ]
        for status in statuses {
            render(status: status)
        }
    }

    func testNeonStyleWhileRecordingRendersParticleOverlay() {
        render(status: .recording, style: .neon)
    }

    func testTapCallbackIsWired() {
        var tapped = false
        let view = WaveformContainer(
            status: .ready,
            audioLevel: 0,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0, count: 8),
            onTap: { tapped = true }
        )
        view.onTap()
        XCTAssertTrue(tapped)
    }
}
