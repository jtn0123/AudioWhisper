import AudioToolbox
import Foundation

/// Converts owned temporary PCM output with fixed-size preparation buffers.
/// The caller transfers complete output to the daemon's existing file lease.
enum RawPCMConverter {
    static let bufferFrames = 4096

    @discardableResult
    static func convert(
        input: URL, output: URL,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> Int {
        try checkCancellation()
        var reference: ExtAudioFileRef?
        let openStatus = ExtAudioFileOpenURL(input as CFURL, &reference)
        guard openStatus == noErr, let file = reference else {
            throw ParakeetError.transcriptionFailed("Failed to open audio file: \(openStatus)")
        }
        defer { ExtAudioFileDispose(file) }
        var format = AudioStreamBasicDescription(
            mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
        let formatStatus = ExtAudioFileSetProperty(
            file, kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &format)
        guard formatStatus == noErr else {
            throw ParakeetError.transcriptionFailed("Failed to set audio format: \(formatStatus)")
        }
        try Data().write(to: output, options: .withoutOverwriting)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: output) } }
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        var samples = [Float](repeating: 0, count: bufferFrames)
        var totalFrames = 0
        while true {
            try checkCancellation()
            var frames = UInt32(bufferFrames)
            var data = Data()
            let status = samples.withUnsafeMutableBytes { bytes in
                let audioBuffer = AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
                var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
                let result = ExtAudioFileRead(file, &frames, &buffers)
                if result == noErr, frames <= bufferFrames {
                    data = Data(bytes.prefix(Int(frames) * MemoryLayout<Float>.size))
                }
                return result
            }
            guard status == noErr, frames <= bufferFrames else {
                throw ParakeetError.transcriptionFailed("Failed to read audio data: \(status)")
            }
            guard frames > 0 else { break }
            try checkCancellation()
            try handle.write(contentsOf: data)
            totalFrames += Int(frames)
        }
        guard totalFrames >= 1600 else { throw ParakeetError.emptyAudio }
        try checkCancellation()
        try handle.close()
        completed = true
        return totalFrames
    }
}
