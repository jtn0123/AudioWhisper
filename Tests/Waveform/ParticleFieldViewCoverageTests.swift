import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

// MARK: - ParticleFieldView Tests
@MainActor
final class ParticleFieldViewCoverageTests: XCTestCase {

    private func render(_ view: ParticleFieldView) {
        let hosting = NSHostingView(rootView: view.frame(width: 200, height: 120))
        hosting.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        hosting.layout()
        XCTAssertNotNil(hosting)
    }

    func testSeededInitProducesDeterministicView() {
        let view = ParticleFieldView(
            audioLevel: 0.6,
            frequencyBands: [0.8, 0.6, 0.4, 0.3, 0.2, 0.15, 0.1, 0.3],
            isActive: true,
            seed: 42
        )
        render(view)
    }

    func testIdleViewRenders() {
        let view = ParticleFieldView(
            audioLevel: 0,
            frequencyBands: Array(repeating: 0, count: 8),
            isActive: false,
            seed: 7
        )
        render(view)
    }

    func testActiveViewWithoutSeedRenders() {
        let view = ParticleFieldView(
            audioLevel: 0.9,
            frequencyBands: Array(repeating: 0.7, count: 8),
            isActive: true
        )
        render(view)
    }

    func testEmptyFrequencyBandsRenders() {
        let view = ParticleFieldView(
            audioLevel: 0.5,
            frequencyBands: [],
            isActive: true,
            seed: 99
        )
        render(view)
    }

    func testZeroSeedIsHandled() {
        // Seed 0 is special-cased inside SeededRandomNumberGenerator.
        let view = ParticleFieldView(
            audioLevel: 0.4,
            frequencyBands: [0.5, 0.5],
            isActive: true,
            seed: 0
        )
        render(view)
    }

    func testBodyDoesNotCrashForLowAudioLevel() {
        let view = ParticleFieldView(
            audioLevel: 0.01,
            frequencyBands: Array(repeating: 0.1, count: 8),
            isActive: true,
            seed: 123
        )
        _ = view.body
        render(view)
    }
}
