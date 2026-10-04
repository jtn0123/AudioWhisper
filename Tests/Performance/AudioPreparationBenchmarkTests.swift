import AVFoundation
import Darwin
import XCTest
@testable import AudioWhisper
@testable import WhisperKit

final class AudioPreparationBenchmarkTests: XCTestCase {
    func testLongAudioPreparationMemoryAndCancellation() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["RUN_AUDIO_BENCHMARK"] == "1")
        let mode = env["PCM_BENCHMARK_MODE"] ?? "pcm-stream"
        let seconds = Int(env["PCM_BENCHMARK_SECONDS"] ?? "10800") ?? 10800
        let frames = seconds * 16000
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("long-audio-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("long.wav")
        try makeAudio(input, frames: frames)
        let start = ContinuousClock.now
        let output = directory.appendingPathComponent("long.raw")
        var count = 0
        var largestChunk = 0
        switch mode {
        case "pcm-stream":
            count = try RawPCMConverter.convert(input: input, output: output)
            largestChunk = RawPCMConverter.bufferFrames
        case "pcm-reference":
            // Whole-file Float32 + Data reference reproduces the old preparation's memory shape.
            let file = try AVAudioFile(forReading: input)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
            try file.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            count = Int(buffer.frameLength)
            try Data(bytes: samples, count: count * 4).write(to: output)
            largestChunk = count
        case "whisper-full":
            let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: input.path)
            count = samples.count
            largestChunk = count
        case "whisper-incremental":
            let stream = try AudioProcessor.loadFileIncrementally(
                fromPath: input.path, chunkDurationSeconds: 120, maxBufferedChunks: 2)
            for try await chunk in stream {
                count += chunk.audioChunk.audioSamples.count
                largestChunk = max(largestChunk, chunk.audioChunk.audioSamples.count)
                chunk.completionSignal()
            }
        default: XCTFail("Unknown benchmark mode: \(mode)")
        }
        XCTAssertEqual(count, frames)
        let elapsed = start.duration(to: .now)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("AUDIO_PREPARATION_BENCHMARK mode=\(mode) seconds=\(seconds) samples=\(count) largestChunk=\(largestChunk) elapsed=\(elapsed) peakRSSBytes=\(usage.ru_maxrss)")
        if mode == "pcm-stream" {
            try await verifyPCMCancellation(input: input, directory: directory)
        } else if mode == "whisper-incremental" {
            try await verifyWhisperCancellation(input: input, frames: frames)
        }
    }

    private func verifyPCMCancellation(input: URL, directory: URL) async throws {
        let task = Task.detached {
            try RawPCMConverter.convert(input: input, output: directory.appendingPathComponent("cancel.raw"))
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: directory.appendingPathComponent("cancel.raw").path),
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cancel.raw").path))
        let cancelStart = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must interrupt long preparation")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cancel.raw").path))
        print("AUDIO_PREPARATION_CANCEL mode=pcm-stream elapsed=\(cancelStart.duration(to: .now)) partialFileRemoved=true")
    }

    private func verifyWhisperCancellation(input: URL, frames: Int) async throws {

        let (started, signal) = AsyncStream<Void>.makeStream()
        let task = Task.detached {
            defer { signal.finish() }
            let stream = try AudioProcessor.loadFileIncrementally(
                fromPath: input.path, chunkDurationSeconds: 120, maxBufferedChunks: 1)
            var consumed = 0
            for try await chunk in stream {
                try Task.checkCancellation()
                consumed += chunk.audioChunk.audioSamples.count
                signal.yield(())
                chunk.completionSignal()
            }
            return consumed
        }
        for await _ in started { break }
        let cancelStart = ContinuousClock.now
        task.cancel()
        do {
            let consumed = try await task.value
            XCTAssertLessThan(consumed, frames)
        } catch { XCTAssertTrue(error is CancellationError) }
        signal.finish()
        print("AUDIO_PREPARATION_CANCEL mode=whisper-incremental elapsed=\(cancelStart.duration(to: .now))")
    }

    private func makeAudio(_ url: URL, frames: Int) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<4096 { samples[index] = Float(sin(Double(index) * 0.07) * 0.25) }
        var remaining = frames
        while remaining > 0 {
            buffer.frameLength = AVAudioFrameCount(min(remaining, 4096))
            try file.write(from: buffer)
            remaining -= Int(buffer.frameLength)
        }
    }
}
