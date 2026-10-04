import Accelerate
import XCTest
@testable import AudioWhisper

@MainActor
final class AudioEngineWaveformTests: XCTestCase {
    func testRMSParityAndRemainderBehavior() {
        let recorder = AudioEngineRecorder()
        let actual = recorder.downsampleForDisplay([1, 2, 3, 4, 999], targetCount: 2)
        XCTAssertEqual(actual.count, 2)
        XCTAssertEqual(actual[0], sqrt(2.5), accuracy: 0.00001)
        XCTAssertEqual(actual[1], sqrt(12.5), accuracy: 0.00001)
    }

    func testEmptyShortAndInvalidTargetsPreserveInput() {
        let recorder = AudioEngineRecorder()
        XCTAssertEqual(recorder.downsampleForDisplay([], targetCount: 128), [])
        for target in [-1, 0, 2, 128] {
            XCTAssertEqual(recorder.downsampleForDisplay([1, -2], targetCount: target), [1, -2])
        }
    }

    func testRepeatedDownsamplingPerformance() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_AUDIO_BENCHMARK"] == "1")
        let recorder = AudioEngineRecorder()
        let samples = (0..<4096).map { Float($0 % 13) / 13 }
        var total: Float = 0
        let iterations = 10000
        let start = ContinuousClock.now
        for _ in 0..<iterations { total += recorder.downsampleForDisplay(samples, targetCount: 128)[0] }
        let elapsed = start.duration(to: .now)
        let referenceStart = ContinuousClock.now
        for _ in 0..<iterations { total += reference(samples, targetCount: 128)[0] }
        let referenceElapsed = referenceStart.duration(to: .now)
        XCTAssertGreaterThan(total, 0)
        print("WAVEFORM_BENCHMARK iterations=\(iterations) direct=\(elapsed) copiedSlices=\(referenceElapsed)")
    }

    private func reference(_ samples: [Float], targetCount: Int) -> [Float] {
        let size = samples.count / targetCount
        return (0..<targetCount).map { index in
            let chunk = Array(samples[(index * size)..<((index + 1) * size)])
            var value: Float = 0
            vDSP_rmsqv(chunk, 1, &value, vDSP_Length(chunk.count))
            return value
        }
    }
}
