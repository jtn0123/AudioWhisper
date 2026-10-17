import AVFAudio
import Foundation

/// A bounded copy of recent audio, independent of the final capture file.
/// Only the opt-in preview allocates this ring; the audio tap never runs inference.
final class RecordingPreviewAudio: @unchecked Sendable {
    static let windowSeconds: Double = 12
    private let lock = NSLock()
    private var ring: SampleRingBuffer?
    private var sampleRate: Double = 0
    private var framesWritten: Int64 = 0

    func configure(enabled: Bool, sampleRate: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.sampleRate = sampleRate
        framesWritten = 0
        ring = enabled && sampleRate >= 8000 && sampleRate <= 192000
            ? SampleRingBuffer(capacity: Int(sampleRate * Self.windowSeconds)) : nil
    }

    func append(_ samples: [Float]) {
        lock.lock()
        ring?.append(contentsOf: samples)
        if ring != nil { framesWritten += Int64(samples.count) }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        ring = nil
        framesWritten = 0
        lock.unlock()
    }

    /// Called off the main/audio threads, at most once per preview inference.
    func snapshot() -> RecordingPreviewSnapshot? {
        lock.lock()
        let rate = sampleRate
        let position = framesWritten
        let samples = ring.flatMap { $0.count >= Int(rate) ? $0.snapshot() : nil }
        lock.unlock()
        guard let samples, RecordingSignalMeter.rms(of: samples) >= RecordingSignalMeter.silenceRMS else { return nil }
        return RecordingPreviewSnapshot(samples: samples, sampleRate: rate, endFrame: position)
    }
}

struct RecordingPreviewSnapshot: Sendable {
    let samples: [Float]
    let sampleRate: Double
    /// Absent for fixture snapshots. Real capture stamps skip duplicate work.
    var endFrame: Int64?

    /// All conversion and temporary-file work happens on the preview worker.
    /// The returned raw PCM is transferred to Parakeet's existing file lease.
    func writePCM() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID())")
        let audio = base.appendingPathExtension("caf")
        let pcm = base.appendingPathExtension("raw")
        defer { try? FileManager.default.removeItem(at: audio) }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw ParakeetError.emptyAudio }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            if let address = source.baseAddress { channel.update(from: address, count: source.count) }
        }
        // Closing the writer before conversion flushes its frame count.
        do {
            let file = try AVAudioFile(forWriting: audio, settings: format.settings)
            try file.write(from: buffer)
        }
        try RawPCMConverter.convert(input: audio, output: pcm)
        return pcm
    }
}
