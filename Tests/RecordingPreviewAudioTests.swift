import XCTest
@testable import AudioWhisper

final class RecordingPreviewAudioTests: XCTestCase {
    func testAudioIsBoundedToRecentSpeechAndClearedBetweenCaptures() throws {
        let audio = RecordingPreviewAudio()
        audio.configure(enabled: true, sampleRate: 8000)
        audio.append((0..<160000).map { Float($0) / 160000 })
        let snapshot = try XCTUnwrap(audio.snapshot())
        XCTAssertEqual(snapshot.samples.count, 96000)
        XCTAssertEqual(snapshot.samples.first, Float(64000) / 160000)
        XCTAssertEqual(snapshot.endFrame, 160000)
        audio.clear()
        XCTAssertNil(audio.snapshot())
        audio.configure(enabled: true, sampleRate: 16000)
        audio.append([Float](repeating: 0.2, count: 16000))
        XCTAssertEqual(audio.snapshot()?.samples.first, 0.2)
        XCTAssertEqual(audio.snapshot()?.endFrame, 16000)
    }

    func testDisabledSilentAndTooShortCapturesNeverReachInference() {
        let audio = RecordingPreviewAudio()
        audio.configure(enabled: false, sampleRate: 16000)
        audio.append([Float](repeating: 0.1, count: 16000))
        XCTAssertNil(audio.snapshot())
        audio.configure(enabled: true, sampleRate: 16000)
        audio.append([Float](repeating: 0, count: 16000))
        XCTAssertNil(audio.snapshot())
        audio.configure(enabled: true, sampleRate: 16000)
        audio.append([Float](repeating: 0.1, count: 1000))
        XCTAssertNil(audio.snapshot())
    }

    func testHardwareRatesBecomeTheDaemonsSixteenKilohertzFloatPCM() throws {
        for rate in [44100.0, 48000.0] {
            let audio = RecordingPreviewSnapshot(samples: [Float](repeating: 0.1, count: Int(rate)), sampleRate: rate)
            let url = try audio.writePCM()
            defer { try? FileManager.default.removeItem(at: url) }
            let bytes = try Data(contentsOf: url)
            XCTAssertEqual(bytes.count / MemoryLayout<Float>.size, 16000, accuracy: 2)
            XCTAssertEqual(bytes.count % MemoryLayout<Float>.size, 0)
        }
    }
}
