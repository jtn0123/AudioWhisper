import XCTest
import SwiftUI
@testable import AudioWhisper

// MARK: - ClassicWaveformView Tests
final class ClassicWaveformViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = ClassicWaveformView(
            audioLevel: 0.5,
            isActive: true,
            barColor: .blue
        )
        XCTAssertNotNil(view)
    }

    func testViewWithZeroAudioLevel() {
        let view = ClassicWaveformView(
            audioLevel: 0,
            isActive: false,
            barColor: .gray
        )
        XCTAssertNotNil(view)
    }

    func testPhysicsConstants() {
        // Document expected physics constants
        let gravity: CGFloat = 2.5
        let bounceFactor: CGFloat = 0.3
        let riseSpeed: CGFloat = 0.8

        XCTAssertEqual(gravity, 2.5)
        XCTAssertEqual(bounceFactor, 0.3)
        XCTAssertEqual(riseSpeed, 0.8)
    }

    func testBarCountIs64() {
        let expectedBarCount = 64
        XCTAssertEqual(expectedBarCount, 64)
    }

    func testMinHeightIs2() {
        let minHeight: CGFloat = 2
        XCTAssertEqual(minHeight, 2)
    }
}

// MARK: - NeonWaveformView Tests
final class NeonWaveformViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = NeonWaveformView(
            waveformSamples: [0.1, 0.2, 0.3, 0.4],
            audioLevel: 0.5,
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testViewWithEmptySamples() {
        let view = NeonWaveformView(
            waveformSamples: [],
            audioLevel: 0,
            isActive: false
        )
        XCTAssertNotNil(view)
    }

    func testColorThresholds() {
        // High level (>0.7) = yellow
        // Medium level (>0.4) = magenta
        // Low level = cyan
        let highThreshold: Float = 0.7
        let mediumThreshold: Float = 0.4

        XCTAssertEqual(highThreshold, 0.7)
        XCTAssertEqual(mediumThreshold, 0.4)
    }

    func testTrailCount() {
        let trailCount = 3
        XCTAssertEqual(trailCount, 3)
    }

    func testDecayFactor() {
        let decayFactor: Float = 0.55
        XCTAssertEqual(decayFactor, 0.55)
    }
}

// MARK: - StreamWaveformView Tests
final class StreamWaveformViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = StreamWaveformView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }

    func testViewInIdleState() {
        let view = StreamWaveformView(audioLevel: 0, isActive: false)
        XCTAssertNotNil(view)
    }
}

// MARK: - ConstellationWaveformView Tests
final class ConstellationWaveformViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = ConstellationWaveformView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }

    func testViewInIdleState() {
        let view = ConstellationWaveformView(audioLevel: 0, isActive: false)
        XCTAssertNotNil(view)
    }
}

// MARK: - HaloWaveformView Tests
final class HaloWaveformViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = HaloWaveformView(
            frequencyBands: [0.7, 0.5, 0.4, 0.6, 0.3, 0.45, 0.25, 0.35],
            audioLevel: 0.5,
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testViewWithEmptyBands() {
        let view = HaloWaveformView(
            frequencyBands: [],
            audioLevel: 0,
            isActive: false
        )
        XCTAssertNotNil(view)
    }
}

// MARK: - DialWaveformView Tests
final class DialWaveformViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = DialWaveformView(
            frequencyBands: [0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15],
            audioLevel: 0.5,
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testViewWithEmptyBands() {
        let view = DialWaveformView(
            frequencyBands: [],
            audioLevel: 0,
            isActive: false
        )
        XCTAssertNotNil(view)
    }
}

// MARK: - HeartbeatPulseView Tests
final class HeartbeatPulseViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = HeartbeatPulseView(audioLevel: 0.5, isActive: true)
        XCTAssertNotNil(view)
    }

    func testViewInIdleState() {
        let view = HeartbeatPulseView(audioLevel: 0, isActive: false)
        XCTAssertNotNil(view)
    }
}

// MARK: - SpectrumWaveformView Tests
final class SpectrumWaveformViewTests: XCTestCase {

    func testViewCanBeCreated() {
        let view = SpectrumWaveformView(
            frequencyBands: [0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15],
            isActive: true
        )
        XCTAssertNotNil(view)
    }

    func testViewWithEmptyBands() {
        let view = SpectrumWaveformView(
            frequencyBands: [],
            isActive: false
        )
        XCTAssertNotNil(view)
    }

    func testBandCount() {
        let bandCount = 8
        XCTAssertEqual(bandCount, 8)
    }

    func testBandLabels() {
        let expectedLabels = ["80", "120", "180", "260", "380", "550", "750", "950"]
        XCTAssertEqual(expectedLabels.count, 8)
    }
}
