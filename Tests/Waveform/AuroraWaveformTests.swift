import XCTest
import SwiftUI
@testable import AudioWhisper

/// Behaviour of the Aurora styles (Neon Dusk, Molten, Electric): heights follow
/// the voice, silence settles, colour crawls left → right, Reduce Motion stills
/// everything but height, and each mountain keeps its own hue.
@MainActor
final class AuroraWaveformTests: IsolatedXCTestCase {
    private let frame = 1.0 / 60

    private func samples(_ level: Float, at time: Double) -> [Float] {
        (0..<64).map { index in
            let phase = Double(index) * 0.19 + time * 9
            return Float(sin(phase) * 0.65 + sin(phase * 2.3) * 0.22) * level
        }
    }

    /// Drives `engine` at 60 fps from `start` for `seconds` at a constant level.
    @discardableResult
    private func run(_ engine: AuroraEngine, level: Float, from start: Double, seconds: Double,
                     reduceMotion: Bool = false) -> Double {
        var time = start
        while time < start + seconds {
            engine.advance(to: time, rawLevel: level, samples: samples(level, at: time), reduceMotion: reduceMotion)
            time += frame
        }
        return time
    }

    // MARK: - Styles

    func testOnlyTheThreeAuroraStylesHavePalettes() {
        let aurora = WaveformStyle.allCases.filter { $0.auroraPalette != nil }
        XCTAssertEqual(aurora, [.neonDusk, .molten, .electric])
        XCTAssertEqual(WaveformStyle.neonDusk.auroraPalette, .neonDusk)
        XCTAssertEqual(WaveformStyle.molten.auroraPalette, .molten)
        XCTAssertEqual(WaveformStyle.electric.auroraPalette, .electric)
        for style in aurora {
            XCTAssertFalse(style.isRadial)
            XCTAssertTrue(style.requiresEnhancedAudio, "Aurora uses the sample buffer for texture")
        }
    }

    func testPalettesHaveFiveCrestAndDeepStops() {
        for palette in [AuroraPalette.neonDusk, .molten, .electric] {
            XCTAssertEqual(palette.crest.count, 5)
            XCTAssertEqual(palette.deep.count, 5)
        }
    }

    // MARK: - Engine

    func testSilenceStaysFlatAndAtRest() {
        let engine = AuroraEngine()
        run(engine, level: 0, from: 0, seconds: 2)
        XCTAssertTrue(engine.isAtRest)
        XCTAssertEqual(engine.values.max() ?? 1, 0, accuracy: 1e-9)
    }

    func testLouderVoiceDrawsTallerMountains() {
        let quiet = AuroraEngine(), loud = AuroraEngine()
        run(quiet, level: 0.25, from: 0, seconds: 1)
        run(loud, level: 0.8, from: 0, seconds: 1)
        XCTAssertGreaterThan(loud.values.max() ?? 0, (quiet.values.max() ?? 0) + 0.1)
        XCTAssertLessThanOrEqual(loud.values.max() ?? 2, 1)
    }

    func testMountainsSettleAfterSpeechStops() {
        let engine = AuroraEngine()
        let end = run(engine, level: 0.7, from: 0, seconds: 1)
        XCTAssertFalse(engine.isAtRest)
        run(engine, level: 0, from: end, seconds: 3)
        XCTAssertTrue(engine.isAtRest)
    }

    func testReflectionKeepsABriefAfterglow() {
        let engine = AuroraEngine()
        let end = run(engine, level: 0.7, from: 0, seconds: 1)
        run(engine, level: 0, from: end, seconds: 0.3)
        XCTAssertGreaterThan(engine.glow.max() ?? 0, engine.values.max() ?? 0)
    }

    func testColourCrawlsForwardAndFasterWithVoice() {
        let quiet = AuroraEngine(), loud = AuroraEngine()
        run(quiet, level: 0, from: 0, seconds: 2)
        run(loud, level: 0.8, from: 0, seconds: 2)
        XCTAssertGreaterThan(quiet.crawl, 0, "Colour idles forward even in silence")
        XCTAssertGreaterThan(loud.crawl, quiet.crawl * 2)
        XCTAssertGreaterThan(loud.glint, 0)
    }

    func testReduceMotionKeepsHeightButStopsCrawlGlintAndTexture() {
        let engine = AuroraEngine()
        run(engine, level: 0.7, from: 0, seconds: 1, reduceMotion: true)
        XCTAssertEqual(engine.crawl, 0)
        XCTAssertEqual(engine.glint, 0)
        XCTAssertGreaterThan(engine.values.max() ?? 0, 0.3, "Height still answers the voice")
        for lobe in 0..<3 {
            let slice = AuroraGeometry.lobe(engine.values, lobe)
            XCTAssertEqual((slice.max() ?? 0) - (slice.min() ?? 0), 0, accuracy: 1e-9,
                           "No sample texture under Reduce Motion")
        }
        XCTAssertEqual(engine.glow, engine.values, "No afterglow lag under Reduce Motion")
    }

    func testRepeatedRedrawAtTheSameTimeIsIdempotent() {
        let engine = AuroraEngine()
        run(engine, level: 0.6, from: 0, seconds: 0.5)
        let values = engine.values, crawl = engine.crawl
        engine.advance(to: 0.5 - frame / 2, rawLevel: 1, samples: [], reduceMotion: false)
        XCTAssertEqual(engine.values, values)
        XCTAssertEqual(engine.crawl, crawl)
    }

    // MARK: - Colour

    /// Each mountain samples its own disjoint slice of the palette, so no
    /// colour any mountain can show is close to a colour another can show.
    func testEachMountainKeepsADistinctHue() {
        let bands = AuroraRenderer.lobeBands
        for (first, second) in [(0, 1), (0, 2), (1, 2)] {
            XCTAssertTrue(bands[first].high < bands[second].low || bands[second].high < bands[first].low)
        }
        func points(_ band: AuroraRenderer.Band) -> [Double] {
            (0...10).map { band.low + (band.high - band.low) * Double($0) / 10 }
        }
        for palette in [AuroraPalette.neonDusk, .molten, .electric] {
            for (first, second) in [(0, 1), (0, 2), (1, 2)] {
                var closest = Double.infinity
                for left in points(bands[first]) {
                    for right in points(bands[second]) {
                        let colorA = AuroraPalette.sample(palette.crest, at: left)
                        let colorB = AuroraPalette.sample(palette.crest, at: right)
                        closest = min(closest, abs(colorA.red - colorB.red) + abs(colorA.green - colorB.green)
                                      + abs(colorA.blue - colorB.blue))
                    }
                }
                XCTAssertGreaterThan(closest, 0.3, "Mountains \(first) and \(second) share a hue")
            }
        }
    }

    func testPaletteSampleIsClampedAndHitsStops() {
        let stops = AuroraPalette.electric.crest
        XCTAssertEqual(AuroraPalette.sample(stops, at: -3), stops[0])
        XCTAssertEqual(AuroraPalette.sample(stops, at: 2), stops[2])
        XCTAssertEqual(AuroraPalette.sample(stops, at: 99), stops[4])
    }

    // MARK: - Rendering

    func testBothShapesRenderColourWhileSpeaking() throws {
        for shape in AuroraShape.allCases {
            let engine = AuroraEngine()
            run(engine, level: 0.7, from: 0, seconds: 1)
            let view = Canvas { context, size in
                AuroraRenderer.draw(shape, palette: .neonDusk, engine: engine, in: &context, size: size)
            }
            .frame(width: 348, height: 70)
            .background(Color.black)
            let renderer = ImageRenderer(content: view)
            let image = try XCTUnwrap(renderer.nsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil))
            XCTAssertGreaterThan(saturatedPixelFraction(image), 0.05, "\(shape) drew no colour")
        }
    }

    private func saturatedPixelFraction(_ image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var saturated = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let channels = pixels[index..<(index + 3)]
            if let high = channels.max(), let low = channels.min(), high > 80, Int(high) - Int(low) > 60 {
                saturated += 1
            }
        }
        return Double(saturated) / Double(width * height)
    }
}
