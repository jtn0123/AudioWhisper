import Observation
import XCTest
@testable import AudioWhisper

/// The Aurora timeline must actually stop once the mountains settle, and the
/// view must learn about it: `settled` is the one observed engine property.
@MainActor
final class AuroraTimelineTests: XCTestCase {
    /// `onChange` is `@Sendable`; this records that it ran without a captured var.
    private final class Flag: @unchecked Sendable { var raised = false }

    private func drive(_ engine: AuroraEngine, level: Float, from start: Double, seconds: Double) -> Double {
        var time = start
        while time < start + seconds {
            let samples = (0..<64).map { Float(sin(Double($0) * 0.3 + time * 9)) * level }
            engine.advance(to: time, rawLevel: level, samples: samples, reduceMotion: false)
            time += AuroraWaveformView.frameInterval
        }
        return time
    }

    func testTheTimelinePausesOnlyOnceIdleAndSettled() {
        let engine = AuroraEngine()
        XCTAssertTrue(AuroraWaveformView.paused(isActive: false, engine: engine), "Nothing to draw before speech")
        XCTAssertFalse(AuroraWaveformView.paused(isActive: true, engine: engine), "Recording always ticks")
        let end = drive(engine, level: 0.7, from: 0, seconds: 1)
        XCTAssertFalse(AuroraWaveformView.paused(isActive: false, engine: engine), "Still settling after speech")
        _ = drive(engine, level: 0, from: end, seconds: 4)
        XCTAssertTrue(AuroraWaveformView.paused(isActive: false, engine: engine))
    }

    func testSettlingNotifiesObserversSoTheViewCanPause() {
        let engine = AuroraEngine()
        let end = drive(engine, level: 0.7, from: 0, seconds: 1)
        XCTAssertFalse(engine.settled)
        let changed = Flag()
        withObservationTracking { _ = engine.settled } onChange: { changed.raised = true }
        _ = drive(engine, level: 0, from: end, seconds: 4)
        XCTAssertTrue(changed.raised)
        XCTAssertTrue(engine.settled)
    }

    func testPerFrameValuesDoNotInvalidateTheView() {
        let engine = AuroraEngine()
        let end = drive(engine, level: 0.7, from: 0, seconds: 0.5)
        let changed = Flag()
        withObservationTracking {
            _ = engine.values
            _ = engine.crawl
            _ = engine.level
        } onChange: { changed.raised = true }
        _ = drive(engine, level: 0.7, from: end, seconds: 0.5)
        XCTAssertFalse(changed.raised, "Height and colour change every frame; observing them would re-run the body each frame")
    }

    func testFrameRateIsCapped() {
        XCTAssertEqual(AuroraWaveformView.frameInterval, 1.0 / 60, accuracy: 1e-9)
    }
}
