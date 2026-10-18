import AVFoundation

/// Copies tap buffers before they expire; a bounded serial writer keeps disk
/// work off the realtime callback. Overflow fails visibly instead of hiding gaps.
final class MeetingAudioSink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.audiowhisper.meeting-audio")
    private let lock = NSLock()
    private var pending = 0
    private var stopped = false
    private var failure: String?
    private var file: AVAudioFile?
    private var current: MeetingAudioChunk?
    private var frames: AVAudioFramePosition = 0
    private var signal = RecordingSignalMeter()
    private var chunks: [MeetingAudioChunk] = []
    private let folder: URL
    private let source: MeetingAudioSource
    private let epoch: TimeInterval
    private let closed: @Sendable (MeetingAudioChunk) -> Void
    private let failed: @Sendable (String) -> Void

    init(folder: URL, source: MeetingAudioSource, epoch: TimeInterval,
         closed: @escaping @Sendable (MeetingAudioChunk) -> Void, failed: @escaping @Sendable (String) -> Void) {
        self.folder = folder
        self.source = source
        self.epoch = epoch
        self.closed = closed
        self.failed = failed
    }

    func append(_ buffer: AVAudioPCMBuffer, time: TimeInterval) {
        lock.lock()
        guard !stopped, failure == nil else { lock.unlock(); return }
        guard pending < 32 else {
            failure = MeetingError.audio.localizedDescription
            lock.unlock()
            failed("Audio could not be written fast enough. Closed chunks were kept.")
            return
        }
        pending += 1
        lock.unlock()
        guard let copy = Self.copy(buffer) else { finishPending(error: MeetingError.audio.localizedDescription); return }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try write(copy, time: time)
                finishPending(error: nil)
            } catch { finishPending(error: error.localizedDescription) }
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer, time: TimeInterval) throws {
        let offset = max(0, time - epoch)
        guard offset.isFinite, offset < 1_800 else { throw MeetingError.bounds }
        if let file {
            let duration = Double(frames) / file.processingFormat.sampleRate
            let expected = (current?.offset ?? offset) + duration
            if file.processingFormat != buffer.format || duration >= 30 || abs(offset - expected) > 0.1 { closeChunk() }
        }
        if file == nil {
            guard chunks.count < 1_000 else { throw MeetingError.bounds }
            let id = UUID()
            let name = "\(source.rawValue)_\(Int(offset * 1000))_\(id.uuidString).caf"
            file = try AVAudioFile(forWriting: folder.appendingPathComponent(name), settings: buffer.format.settings,
                                   commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            current = MeetingAudioChunk(id: id, source: source, filename: name, offset: offset, duration: 0)
            frames = 0
            signal = RecordingSignalMeter()
        }
        try file?.write(from: buffer)
        frames += AVAudioFramePosition(buffer.frameLength)
        if buffer.format.commonFormat == .pcmFormatFloat32 {
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
            let rms = buffers.compactMap { audio -> Float? in
                guard let data = audio.mData else { return nil }
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                    count: Int(audio.mDataByteSize) / MemoryLayout<Float>.size)
                return RecordingSignalMeter.rms(of: Array(samples))
            }.max() ?? 0
            signal.add(rms: rms, frames: Int(buffer.frameLength), sampleRate: buffer.format.sampleRate)
        }
    }

    private func closeChunk() {
        guard let rate = file?.processingFormat.sampleRate, let current else { return }
        let chunk = MeetingAudioChunk(id: current.id, source: source, filename: current.filename,
                                     offset: current.offset, duration: Double(frames) / rate,
                                     hasSignal: signal.frames > 0 ? !signal.isSilent : nil)
        self.file = nil // Close the CAF before publishing it to the manifest.
        self.current = nil
        if frames > 0 { chunks.append(chunk); closed(chunk) }
    }

    private func finishPending(error: String?) {
        lock.lock()
        pending -= 1
        let firstFailure = error != nil && failure == nil
        if let error { failure = error }
        lock.unlock()
        if firstFailure, let error { failed(error) }
    }

    func finish() async -> [MeetingAudioChunk] {
        lock.lock(); stopped = true; lock.unlock()
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { continuation.resume(returning: []); return }
                closeChunk()
                continuation.resume(returning: chunks)
            }
        }
    }

    private static func copy(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else { return nil }
        copy.frameLength = source.frameLength
        let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: source.audioBufferList))
        let output = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(input, output) {
            guard let src = from.mData, let dst = to.mData, from.mDataByteSize <= to.mDataByteSize else { return nil }
            memcpy(dst, src, Int(from.mDataByteSize))
        }
        return copy
    }
}
