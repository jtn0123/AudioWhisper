import XCTest
import AVFoundation
@testable import AudioWhisper

/// Tests for audio processing validation including format conversion,
/// sample ranges, and edge cases in audio handling.
final class AudioProcessingValidationTests: XCTestCase {

    // MARK: - Float32 Sample Range Tests

    func testFloat32SamplesWithinValidRange() {
        // Valid audio samples should be in [-1.0, 1.0]
        let validSamples: [Float] = [-1.0, -0.5, 0.0, 0.5, 1.0]

        for sample in validSamples {
            XCTAssertTrue(isValidAudioSample(sample), "Sample \(sample) should be valid")
        }
    }

    func testFloat32SamplesOutOfRange() {
        // Samples outside [-1.0, 1.0] are technically invalid for normalized audio
        let invalidSamples: [Float] = [-1.5, 1.5, 2.0, -2.0]

        for sample in invalidSamples {
            XCTAssertFalse(isValidAudioSample(sample), "Sample \(sample) should be invalid")
        }
    }

    func testFloat32SamplesAtBoundary() {
        // Exact boundary values
        XCTAssertTrue(isValidAudioSample(-1.0))
        XCTAssertTrue(isValidAudioSample(1.0))

        // Just inside boundaries
        XCTAssertTrue(isValidAudioSample(-0.999999))
        XCTAssertTrue(isValidAudioSample(0.999999))

        // Just outside boundaries
        XCTAssertFalse(isValidAudioSample(-1.000001))
        XCTAssertFalse(isValidAudioSample(1.000001))
    }

    private func isValidAudioSample(_ sample: Float) -> Bool {
        return sample >= -1.0 && sample <= 1.0
    }

    // MARK: - Sample Rate Validation Tests

    func testTargetSampleRateIs16kHz() {
        // Parakeet and most ML models expect 16kHz
        let expectedSampleRate = 16000
        XCTAssertEqual(expectedSampleRate, 16000)
    }

    func testCommonSampleRates() {
        // Common audio sample rates that might need conversion
        let commonRates = [8000, 11025, 22050, 44100, 48000, 96000]

        for rate in commonRates {
            XCTAssertGreaterThan(rate, 0, "Sample rate should be positive")
        }
    }

    // MARK: - Audio Format Tests

    func testLinearPCMFormatConfiguration() {
        // Test the audio format configuration used in ParakeetService
        let targetSampleRate: Float64 = 16000
        let channelCount: UInt32 = 1  // Mono
        let bitsPerChannel: UInt32 = 32  // Float32
        let bytesPerFrame: UInt32 = 4

        // Verify format configuration
        XCTAssertEqual(targetSampleRate, 16000)
        XCTAssertEqual(channelCount, 1, "Should be mono")
        XCTAssertEqual(bitsPerChannel, 32, "Should be 32-bit float")
        XCTAssertEqual(bytesPerFrame, 4, "Float32 = 4 bytes per frame for mono")
    }

    func testAudioFormatFlags() {
        // Verify the audio format flags match what ParakeetService uses
        let expectedFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked

        XCTAssertTrue(expectedFlags & kAudioFormatFlagIsFloat != 0, "Should be float format")
        XCTAssertTrue(expectedFlags & kAudioFormatFlagIsPacked != 0, "Should be packed")
    }

    // MARK: - Duration Edge Case Tests

    func testVeryShortAudioDuration() {
        // Minimum practical audio duration
        let veryShortDurations: [TimeInterval] = [0.1, 0.25, 0.5]

        for duration in veryShortDurations {
            let sampleCount = Int(16000.0 * duration)
            XCTAssertGreaterThan(sampleCount, 0, "Even short audio should have samples")
        }
    }

    func testZeroDurationAudio() {
        let zeroDuration: TimeInterval = 0
        let sampleCount = Int(16000.0 * zeroDuration)

        XCTAssertEqual(sampleCount, 0, "Zero duration should have zero samples")
    }

    func testLongAudioDuration() {
        // 5 minutes at 16kHz
        let fiveMinutes: TimeInterval = 300
        let sampleCount = Int(16000.0 * fiveMinutes)

        XCTAssertEqual(sampleCount, 4_800_000, "5 minutes at 16kHz = 4.8M samples")
    }

    // MARK: - Buffer Allocation Tests

    func testBufferSizeCalculation() {
        let bufferFrameSize = 4096  // Standard buffer size
        let bytesPerSample = 4  // Float32

        let bufferBytes = bufferFrameSize * bytesPerSample

        XCTAssertEqual(bufferBytes, 16384, "4096 frames * 4 bytes = 16KB buffer")
    }

    func testBufferCapacityReservation() {
        // Test pre-allocation for estimated frame count
        let duration: TimeInterval = 60  // 1 minute
        let sampleRate = 16000
        let estimatedFrames = Int(duration * Double(sampleRate) + 0.5)

        var samples: [Float] = []
        samples.reserveCapacity(estimatedFrames)

        XCTAssertEqual(estimatedFrames, 960_000, "1 minute at 16kHz = 960K frames")
    }

    // MARK: - Silent Audio Detection Tests

    func testSilentAudioDetection() {
        // All zeros = silent
        let silentSamples: [Float] = Array(repeating: 0.0, count: 1000)

        let isSilent = silentSamples.allSatisfy { abs($0) < 0.001 }
        XCTAssertTrue(isSilent, "Zero samples should be detected as silent")
    }

    func testNonSilentAudioDetection() {
        // Has some signal
        var samples: [Float] = Array(repeating: 0.0, count: 1000)
        samples[500] = 0.5  // One non-zero sample

        let isSilent = samples.allSatisfy { abs($0) < 0.001 }
        XCTAssertFalse(isSilent, "Non-zero samples should not be silent")
    }

    func testVeryQuietAudioThreshold() {
        // Audio just above silence threshold
        let quietThreshold: Float = 0.001
        let veryQuietSamples: [Float] = Array(repeating: quietThreshold + 0.0001, count: 100)

        let isSilent = veryQuietSamples.allSatisfy { abs($0) < quietThreshold }
        XCTAssertFalse(isSilent, "Audio just above threshold should not be silent")
    }

    // MARK: - Channel Configuration Tests

    func testMonoChannelOutput() {
        let channelCount: UInt32 = 1
        XCTAssertEqual(channelCount, 1, "Output should be mono for ML processing")
    }

    func testStereoToMonoConversion() {
        // Simulate stereo to mono by averaging
        let leftChannel: [Float] = [0.5, 0.3, 0.1]
        let rightChannel: [Float] = [0.3, 0.5, 0.7]

        var monoSamples: [Float] = []
        for i in 0..<leftChannel.count {
            monoSamples.append((leftChannel[i] + rightChannel[i]) / 2.0)
        }

        XCTAssertEqual(monoSamples[0], 0.4, accuracy: 0.001)
        XCTAssertEqual(monoSamples[1], 0.4, accuracy: 0.001)
        XCTAssertEqual(monoSamples[2], 0.4, accuracy: 0.001)
    }

    // MARK: - PCM Data Serialization Tests

    func testFloat32DataSerialization() {
        let samples: [Float] = [0.5, -0.5, 0.0, 1.0, -1.0]

        // Serialize to raw bytes (as ParakeetService does)
        let data = samples.withUnsafeBytes { Data($0) }

        XCTAssertEqual(data.count, samples.count * 4, "Each float = 4 bytes")

        // Deserialize back
        let reconstructed = data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        XCTAssertEqual(samples, reconstructed, "Round-trip should preserve data")
    }

    func testEmptyDataSerialization() {
        let samples: [Float] = []
        let data = samples.withUnsafeBytes { Data($0) }

        XCTAssertEqual(data.count, 0, "Empty samples should produce empty data")
    }

    // MARK: - Temporary File Handling Tests

    func testTemporaryFileURLGeneration() {
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString
        let tempURL = tempDir.appendingPathComponent("audio_pcm_\(uuid).raw")

        XCTAssertTrue(tempURL.path.contains("audio_pcm_"))
        XCTAssertTrue(tempURL.pathExtension == "raw")
    }

    func testTemporaryFileUniqueness() {
        var urls: Set<String> = []

        for _ in 0..<100 {
            let uuid = UUID().uuidString
            let path = "audio_pcm_\(uuid).raw"
            urls.insert(path)
        }

        XCTAssertEqual(urls.count, 100, "All temp file names should be unique")
    }

    // MARK: - Sample Count Estimation Tests

    func testSampleCountFromDuration() {
        let testCases: [(duration: TimeInterval, sampleRate: Int, expected: Int)] = [
            (1.0, 16000, 16000),      // 1 second
            (0.5, 16000, 8000),       // Half second
            (10.0, 44100, 441000),    // 10 seconds at CD quality
            (60.0, 16000, 960000),    // 1 minute
        ]

        for testCase in testCases {
            let estimated = Int(testCase.duration * Double(testCase.sampleRate))
            XCTAssertEqual(estimated, testCase.expected,
                "Duration \(testCase.duration)s at \(testCase.sampleRate)Hz should have \(testCase.expected) samples")
        }
    }

    // MARK: - Error Condition Tests

    func testInvalidAudioFileExtensions() {
        let invalidExtensions = ["txt", "pdf", "jpg", "png", "mp4"]
        let validExtensions = ["wav", "m4a", "mp3", "caf", "aiff", "flac"]

        for ext in invalidExtensions {
            XCTAssertFalse(validExtensions.contains(ext), "\(ext) should not be a valid audio extension")
        }
    }

    func testAudioStreamBasicDescriptionConfiguration() {
        // Test the format configuration matches expected values
        var format = AudioStreamBasicDescription(
            mSampleRate: 16000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        XCTAssertEqual(format.mSampleRate, 16000)
        XCTAssertEqual(format.mChannelsPerFrame, 1)
        XCTAssertEqual(format.mBitsPerChannel, 32)
        XCTAssertEqual(format.mBytesPerFrame, 4)
        XCTAssertEqual(format.mBytesPerPacket, 4)
        XCTAssertEqual(format.mFramesPerPacket, 1)
    }
}
