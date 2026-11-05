import Foundation

/// How long to wait for each daemon request before giving up and restarting
/// the daemon. One fixed 60-second limit used to kill legitimate work: a
/// 4,096-token cleanup on the 27B model, or a long Parakeet file, runs for
/// minutes. Each budget below covers a cold model load plus the work implied
/// by the input, sized for the slowest supported model.
enum MLRequestTimeout {
    /// Covers loading a model from disk (the largest cleanup model is ~12 GB).
    static let modelLoadSeconds: UInt64 = 90
    static let ping: UInt64 = 15
    static let warmup: UInt64 = 300
    static let maximum: UInt64 = 2 * 60 * 60

    /// The daemon reads raw float32 PCM. 16 kHz is the lowest rate it is fed,
    /// so it gives the longest (safest) duration estimate for a file size.
    private static let pcmBytesPerSecond = 16_000 * MemoryLayout<Float>.size
    /// Parakeet runs far faster than real time; budget one second of work per
    /// two seconds of audio to leave headroom on slower Macs.
    private static let secondsPerAudioSecond = 0.5
    /// Conservative generation speed for the largest cleanup model.
    private static let tokensPerSecond = 8.0

    static func transcribe(pcmBytes: Int) -> UInt64 {
        let audioSeconds = Double(max(0, pcmBytes)) / Double(pcmBytesPerSecond)
        return clamp(Double(modelLoadSeconds) + audioSeconds * secondsPerAudioSecond)
    }

    /// Mirrors `correction.py`: `max_tokens = clamp(words × 4, 128, 4096)`,
    /// and a reply that comes back empty is generated a second time.
    static func correct(text: String) -> UInt64 {
        let words = text.split(whereSeparator: \.isWhitespace).count
        let maxTokens = Double(min(4096, max(128, words * 4)))
        return clamp(Double(modelLoadSeconds) + 2 * maxTokens / tokensPerSecond)
    }

    /// Mirrors `correction.py`'s fixed 2,048-token summary budget, plus time
    /// to read a long transcript into the prompt.
    static func summarize(text: String) -> UInt64 {
        let words = Double(text.split(whereSeparator: \.isWhitespace).count)
        return clamp(Double(modelLoadSeconds) + 2048 / tokensPerSecond + words / 100)
    }

    private static func clamp(_ seconds: Double) -> UInt64 {
        UInt64(min(Double(maximum), seconds).rounded(.up))
    }
}
