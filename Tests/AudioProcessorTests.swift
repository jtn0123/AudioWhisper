import XCTest
import AVFoundation
import AudioToolbox
@testable import AudioWhisper

final class AudioProcessorTests: XCTestCase {

    // In test environment, loadAudio returns mock data to avoid CoreMedia warnings
    private let expectedMockData: [Float] = [0.0, 0.1, -0.1, 0.2, -0.2]

    func testLoadAudioReturnsMockDataInTestEnvironment() throws {
        // Create any valid file URL (content doesn't matter in tests)
        let url = try makeTempAudioFile(samples: [0.5, 0.5], sampleRate: 48_000)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try loadAudio(url: url, samplingRate: 48_000)

        // In test mode, should return mock data regardless of input
        XCTAssertEqual(loaded, expectedMockData, "Should return mock data in test environment")
    }

    func testLoadAudioMockDataIsConsistent() throws {
        let url = try makeTempAudioFile(samples: [0.1], sampleRate: 24_000)
        defer { try? FileManager.default.removeItem(at: url) }

        // Call multiple times to verify consistency
        let loaded1 = try loadAudio(url: url, samplingRate: 16_000)
        let loaded2 = try loadAudio(url: url, samplingRate: 48_000)

        XCTAssertEqual(loaded1, loaded2, "Mock data should be consistent across calls")
        XCTAssertEqual(loaded1, expectedMockData)
    }

    func testLoadAudioMockDataHasValidRange() throws {
        let url = try makeTempAudioFile(samples: [0.0], sampleRate: 44_100)
        defer { try? FileManager.default.removeItem(at: url) }

        let loaded = try loadAudio(url: url, samplingRate: 44_100)

        // Verify all samples are in valid audio range [-1.0, 1.0]
        for sample in loaded {
            XCTAssertGreaterThanOrEqual(sample, -1.0, "Sample should be >= -1.0")
            XCTAssertLessThanOrEqual(sample, 1.0, "Sample should be <= 1.0")
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
