import AVFAudio
import XCTest
@testable import AudioWhisper

final class RawPCMConverterTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("pcm-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testExactMonoOutputAcrossChunksAndPartialFinalChunk() throws {
        let frames = 4096 * 3 + 177
        let input = try makeAudio(frames: frames)
        let output = directory.appendingPathComponent("output.raw")
        XCTAssertEqual(try RawPCMConverter.convert(input: input, output: output), frames)
        let data = try Data(contentsOf: output)
        XCTAssertEqual(data.count, frames * 4)
        data.withUnsafeBytes { bytes in
            for offset in stride(from: 0, to: data.count, by: 4) {
                XCTAssertEqual(bytes.loadUnaligned(fromByteOffset: offset, as: Float.self), 0.25, accuracy: 0.00001)
            }
        }
    }

    func testResamples48kHzTo16kHz() throws {
        let input = try makeAudio(frames: 48000, sampleRate: 48000)
        let output = directory.appendingPathComponent("resampled.raw")
        let frames = try RawPCMConverter.convert(input: input, output: output)
        XCTAssertEqual(Double(frames), 16000, accuracy: 2)
        XCTAssertEqual(try Data(contentsOf: output).count, frames * 4)
    }

    func testNearEmptyAudioRemovesPartialOutput() throws {
        let input = try makeAudio(frames: 1500)
        let output = directory.appendingPathComponent("empty.raw")
        XCTAssertThrowsError(try RawPCMConverter.convert(input: input, output: output)) {
            XCTAssertEqual($0 as? ParakeetError, .emptyAudio)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testCancellationAfterFirstChunkRemovesPartialOutput() throws {
        let input = try makeAudio(frames: 20000)
        let output = directory.appendingPathComponent("cancelled.raw")
        var checks = 0
        XCTAssertThrowsError(try RawPCMConverter.convert(input: input, output: output, checkCancellation: {
            checks += 1
            if checks == 4 {
                XCTAssertGreaterThan((try Data(contentsOf: output)).count, 0)
                throw CancellationError()
            }
        })) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testErrorDuringPreparationRemovesPartialOutput() throws {
        let input = try makeAudio(frames: 20000)
        let output = directory.appendingPathComponent("failed.raw")
        var checks = 0
        XCTAssertThrowsError(try RawPCMConverter.convert(input: input, output: output, checkCancellation: {
            checks += 1
            if checks == 4 { throw CocoaError(.fileWriteOutOfSpace) }
        })) { XCTAssertEqual(($0 as? CocoaError)?.code, .fileWriteOutOfSpace) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testInvalidInputAndExistingDestinationArePreserved() throws {
        let output = directory.appendingPathComponent("existing.raw")
        try Data("keep".utf8).write(to: output)
        XCTAssertThrowsError(try RawPCMConverter.convert(
            input: directory.appendingPathComponent("missing.wav"), output: output))
        let input = try makeAudio(frames: 5000)
        XCTAssertThrowsError(try RawPCMConverter.convert(input: input, output: output))
        XCTAssertEqual(try Data(contentsOf: output), Data("keep".utf8))
    }

    private func makeAudio(frames: Int, sampleRate: Double = 16000) throws -> URL {
        let url = directory.appendingPathComponent("input.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var remaining = frames
        while remaining > 0 {
            buffer.frameLength = AVAudioFrameCount(min(remaining, 4096))
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for index in 0..<Int(buffer.frameLength) { samples[index] = 0.25 }
            try file.write(from: buffer)
            remaining -= Int(buffer.frameLength)
        }
        return url
    }
}
