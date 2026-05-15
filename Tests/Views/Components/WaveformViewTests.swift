import XCTest
@testable import AudioWhisper

/// Smoke tests confirming each waveform renderer view constructs with the
/// initializer signature the redesign settled on. The internal animation /
/// smoothing logic the old `testable*` helpers covered was removed when the
/// renderers were rewritten, so these views are now exercised via init only.
final class WaveformViewTests: XCTestCase {

    func testSpectrumWaveformViewConstructs() {
        let view = SpectrumWaveformView(
            frequencyBands: [0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15],
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testSpectrumWaveformViewConstructsWithEmptyBands() {
        let view = SpectrumWaveformView(frequencyBands: [], isActive: false)
        XCTAssertNotNil(view)
    }

    func testStreamWaveformViewConstructs() {
        let view = StreamWaveformView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }

    func testConstellationWaveformViewConstructs() {
        let view = ConstellationWaveformView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }

    func testHaloWaveformViewConstructs() {
        let view = HaloWaveformView(
            frequencyBands: [0.7, 0.5, 0.4, 0.6, 0.3, 0.45, 0.25, 0.35],
            audioLevel: 0.5,
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testDialWaveformViewConstructs() {
        let view = DialWaveformView(
            frequencyBands: [0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15],
            audioLevel: 0.5,
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testHeartbeatPulseViewConstructs() {
        let view = HeartbeatPulseView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }
}
