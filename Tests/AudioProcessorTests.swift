import XCTest
import AVFoundation
import AudioToolbox
@testable import AudioWhisper

final class AudioProcessorTests: XCTestCase {
    func testLoadAudioReadsSamplesVerbatimAtSameRate() throws {
        let originalSamples: [Float] = [0, 0.25, -0.25, 0.75, -0.75]
        let url = try makeTempAudioFile(samples: originalSamples, sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try loadAudio(url: url, samplingRate: 48_000)

        XCTAssertEqual(loaded.count, originalSamples.count)
        zip(loaded, originalSamples).forEach { loadedSample, expected in
            XCTAssertEqual(loadedSample, expected, accuracy: 0.0001)
        }
    }

    func testLoadAudioResamplesToRequestedRate() throws {
        let duration: Double = 0.05 // seconds
        let sourceRate: Double = 24_000
        let targetRate = 48_000
        let frameCount = Int(sourceRate * duration)
        let sineWave = (0..<frameCount).map { index -> Float in
            let theta = Double(index) / sourceRate * 2 * Double.pi * 440
            return Float(sin(theta))
        }

        let url = try makeTempAudioFile(samples: sineWave, sampleRate: sourceRate)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try loadAudio(url: url, samplingRate: targetRate)

        let expectedFrames = Int(duration * Double(targetRate))
        XCTAssertLessThanOrEqual(abs(loaded.count - expectedFrames), 4, "Resampled frame count should match target rate within tolerance")
        XCTAssertNotEqual(loaded.prefix(10).reduce(0, +), 0, "Resampled data should retain non-zero content")
    }

    func testLoadAudioThrowsOpenFailedForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).wav")

        XCTAssertThrowsError(try loadAudio(url: url, samplingRate: 44_100)) { error in
            guard case let AudioLoadError.openFailed(status) = error else {
                return XCTFail("Expected openFailed error")
            }
            XCTAssertNotEqual(status, noErr)
        }
    }

    // MARK: - Helpers

    /// Creates a WAV file directly without using AVAudioFile to avoid CoreMedia framework warnings
    private func makeTempAudioFile(samples: [Float], sampleRate: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("audio-\(UUID().uuidString).wav")

        // Build WAV file header and data
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 32
        let bytesPerSample = bitsPerSample / 8
        let dataSize = UInt32(samples.count * Int(bytesPerSample))
        let sampleRateInt = UInt32(sampleRate)

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(contentsOf: withUnsafeBytes(of: (36 + dataSize).littleEndian) { Array($0) })
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // chunk size
        data.append(contentsOf: withUnsafeBytes(of: UInt16(3).littleEndian) { Array($0) }) // format = IEEE float
        data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: sampleRateInt.littleEndian) { Array($0) })
        let byteRate = sampleRateInt * UInt32(numChannels) * UInt32(bytesPerSample)
        data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        let blockAlign = numChannels * bytesPerSample
        data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        // Sample data (32-bit float)
        for sample in samples {
            data.append(contentsOf: withUnsafeBytes(of: sample) { Array($0) })
        }

        try data.write(to: url)
        return url
    }
}
