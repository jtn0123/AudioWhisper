import AVFAudio
import QuartzCore

/// Where a warm input's buffers go: into a short pre-roll while nobody is
/// recording, or straight to the recorder while someone is.
///
/// `receive` runs on the engine's tap thread; the rest on the main actor. One
/// lock orders them, so the pre-roll always reaches the recorder before the
/// first live buffer, and nothing reaches it after `detach` returns.
final class AudioFeed: @unchecked Sendable {
    /// How much audio from before the shortcut a recording keeps.
    static let preRollDuration: TimeInterval = 0.3

    private let lock = NSLock()
    private let clock: () -> TimeInterval
    private var sink: ((AVAudioPCMBuffer) -> Void)?
    private var preRoll: [AVAudioPCMBuffer] = []
    private var lastDelivery: TimeInterval?

    init(clock: @escaping () -> TimeInterval = CACurrentMediaTime) {
        self.clock = clock
    }

    func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        lastDelivery = clock()
        if let sink {
            sink(buffer)
        } else if let copy = Self.copy(buffer) {
            // The engine may reuse a tap buffer once the tap returns.
            preRoll.append(copy)
            trimPreRoll(sampleRate: buffer.format.sampleRate)
        }
    }

    /// Sends the pre-roll to `sink`, then every buffer that follows.
    func attach(_ sink: @escaping (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        preRoll.forEach(sink)
        preRoll.removeAll()
        self.sink = sink
    }

    func detach() {
        lock.lock()
        defer { lock.unlock() }
        sink = nil
        preRoll.removeAll()
    }

    /// Whether the input delivered audio within `window`: a running engine can
    /// still have gone quiet after sleep or a device change.
    func isFlowing(within window: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let lastDelivery else { return false }
        return clock() - lastDelivery <= window
    }

    var preRollFrames: AVAudioFrameCount {
        lock.lock()
        defer { lock.unlock() }
        return preRoll.reduce(0) { $0 + $1.frameLength }
    }

    /// Drops whole buffers from the front while the rest still covers the
    /// pre-roll duration.
    private func trimPreRoll(sampleRate: Double) {
        let limit = AVAudioFrameCount(Self.preRollDuration * sampleRate)
        var frames = preRoll.reduce(0) { $0 + $1.frameLength }
        while let first = preRoll.first, frames - first.frameLength >= limit {
            frames -= first.frameLength
            preRoll.removeFirst()
        }
    }

    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, target) {
            guard let input = from.mData, let output = to.mData else { continue }
            memcpy(output, input, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}
