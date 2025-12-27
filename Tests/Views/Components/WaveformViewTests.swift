import XCTest
@testable import AudioWhisper

final class WaveformViewTests: XCTestCase {

    // MARK: - CircularSpectrumView Tests

    func testCircularBandIndexMappingForFirstHalf() {
        // First 8 bars map directly to bands 0-7
        for i in 0..<8 {
            XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: i), i)
        }
    }

    func testCircularBandIndexMappingForSecondHalf() {
        // Last 8 bars mirror back: 8->7, 9->6, 10->5, etc.
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 8), 7)
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 9), 6)
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 10), 5)
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 11), 4)
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 12), 3)
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 13), 2)
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 14), 1)
        XCTAssertEqual(CircularSpectrumView.testableBandIndex(for: 15), 0)
    }

    func testCircularIdleBreathValueRange() {
        // Idle breathing should produce values in expected range (0.05 to 0.20)
        for barIndex in 0..<16 {
            for phase in stride(from: 0.0, to: 2 * .pi, by: 0.5) {
                let value = CircularSpectrumView.testableIdleBreathValue(phase: phase, barIndex: barIndex)
                XCTAssertGreaterThanOrEqual(value, 0.05, "Breath value should be >= 0.05")
                XCTAssertLessThanOrEqual(value, 0.20, "Breath value should be <= 0.20")
            }
        }
    }

    func testCircularSmoothedLevelFastRise() {
        // When target > current, should rise quickly (70% towards target)
        let current: Float = 0.2
        let target: Float = 0.8
        let result = CircularSpectrumView.testableSmoothedLevel(current: current, target: target)

        // Should be closer to target than current
        XCTAssertGreaterThan(result, current)
        XCTAssertLessThan(result, target)
        // Specifically: 0.2 * 0.3 + 0.8 * 0.7 = 0.06 + 0.56 = 0.62
        XCTAssertEqual(result, 0.62, accuracy: 0.001)
    }

    func testCircularSmoothedLevelSlowDecay() {
        // When target < current, should decay slowly (10% towards target)
        let current: Float = 0.8
        let target: Float = 0.2
        let result = CircularSpectrumView.testableSmoothedLevel(current: current, target: target)

        // Should be closer to current than target
        XCTAssertGreaterThan(result, target)
        XCTAssertLessThan(result, current)
        // Specifically: 0.8 * 0.9 + 0.2 * 0.1 = 0.72 + 0.02 = 0.74
        XCTAssertEqual(result, 0.74, accuracy: 0.001)
    }

    // MARK: - SpectrumWaveformView Tests

    func testSpectrumGainBoostApplied() {
        // 70% gain boost (multiply by 1.7)
        XCTAssertEqual(SpectrumWaveformView.testableApplyGainBoost(0.5), 0.85, accuracy: 0.001)
        XCTAssertEqual(SpectrumWaveformView.testableApplyGainBoost(0.4), 0.68, accuracy: 0.001)
    }

    func testSpectrumGainBoostClampedAtMax() {
        // Values that would exceed 1.0 are clamped
        XCTAssertEqual(SpectrumWaveformView.testableApplyGainBoost(0.7), 1.0)
        XCTAssertEqual(SpectrumWaveformView.testableApplyGainBoost(1.0), 1.0)
    }

    func testSpectrumIdleBreathValueRange() {
        // Idle breathing should produce values in expected range (0 to 0.08)
        for bandIndex in 0..<8 {
            for phase in stride(from: 0.0, to: 2 * .pi, by: 0.5) {
                let value = SpectrumWaveformView.testableIdleBreathValue(phase: phase, bandIndex: bandIndex)
                XCTAssertGreaterThanOrEqual(value, 0.0, "Breath value should be >= 0")
                XCTAssertLessThanOrEqual(value, 0.08, "Breath value should be <= 0.08")
            }
        }
    }

    func testSpectrumSmoothedLevelInstantAttack() {
        // When target > current, should jump immediately to target
        let current: Float = 0.2
        let target: Float = 0.8
        let result = SpectrumWaveformView.testableSmoothedLevel(current: current, target: target)

        XCTAssertEqual(result, target)
    }

    func testSpectrumSmoothedLevelGradualDecay() {
        // When target < current, should decay gradually (25% towards target)
        let current: Float = 0.8
        let target: Float = 0.2
        let result = SpectrumWaveformView.testableSmoothedLevel(current: current, target: target)

        // Specifically: 0.8 * 0.75 + 0.2 * 0.25 = 0.6 + 0.05 = 0.65
        XCTAssertEqual(result, 0.65, accuracy: 0.001)
    }

    func testSpectrumPeakDecayNewPeak() {
        // When level exceeds current peak, new peak is set
        let currentPeak: Float = 0.5
        let newLevel: Float = 0.8
        let result = SpectrumWaveformView.testablePeakDecay(current: currentPeak, level: newLevel)

        XCTAssertEqual(result, newLevel)
    }

    func testSpectrumPeakDecaySlowFade() {
        // When level is below peak, peak slowly decays
        let currentPeak: Float = 0.5
        let level: Float = 0.3
        let result = SpectrumWaveformView.testablePeakDecay(current: currentPeak, level: level)

        // Should be slightly below current peak
        XCTAssertEqual(result, 0.49, accuracy: 0.001)
    }

    func testSpectrumPeakDecayNeverNegative() {
        // Peak should never go below zero
        let currentPeak: Float = 0.005
        let level: Float = 0.0
        let result = SpectrumWaveformView.testablePeakDecay(current: currentPeak, level: level)

        XCTAssertEqual(result, 0.0)
    }

    // MARK: - Consistency Tests

    func testCircularMirroringIsSymmetric() {
        // Bars 0 and 15 should map to same band
        XCTAssertEqual(
            CircularSpectrumView.testableBandIndex(for: 0),
            CircularSpectrumView.testableBandIndex(for: 15)
        )
        // Bars 1 and 14 should map to same band
        XCTAssertEqual(
            CircularSpectrumView.testableBandIndex(for: 1),
            CircularSpectrumView.testableBandIndex(for: 14)
        )
        // Bars 7 and 8 should map to same band
        XCTAssertEqual(
            CircularSpectrumView.testableBandIndex(for: 7),
            CircularSpectrumView.testableBandIndex(for: 8)
        )
    }
}
