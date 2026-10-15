import Accelerate
import Foundation

/// Loudness facts about one capture, accumulated on the audio thread.
///
/// WhisperKit 1.1 hard-codes `noSpeechProb` to 0 (TextDecoder leaves it
/// unimplemented), so its no-speech filter never fires and a silent take is
/// decoded anyway — usually into an invented "Thank you." This meter is what
/// lets the app recognise a dead microphone live and refuse to transcribe a
/// recording that never carried a signal.
///
/// The threshold is deliberately conservative: it flags a muted input, a wrong
/// device or a virtual input with nothing routed to it, not a quiet speaker.
/// Any buffer louder than about -60 dBFS clears the recording.
struct RecordingSignalMeter: Equatable, Sendable {
    /// RMS below which a buffer is treated as silence (about -60 dBFS).
    static let silenceRMS: Float = 0.001
    /// How long a capture must stay silent before the live warning appears.
    static let liveWarningDelay: TimeInterval = 2.5

    private(set) var peakRMS: Float = 0
    private(set) var frames: Int64 = 0
    private(set) var sampleRate: Double = 0

    var duration: TimeInterval { sampleRate > 0 ? Double(frames) / sampleRate : 0 }

    /// True when no buffer in the capture rose above `silenceRMS`.
    var isSilent: Bool { frames > 0 && peakRMS < Self.silenceRMS }

    /// The live warning: silent so far, for long enough that it is not just the
    /// first moments before someone starts speaking.
    var warrantsSilenceWarning: Bool { isSilent && duration >= Self.liveWarningDelay }

    mutating func add(_ samples: [Float], sampleRate rate: Double) {
        guard !samples.isEmpty else { return }
        add(rms: Self.rms(of: samples), frames: samples.count, sampleRate: rate)
    }

    mutating func add(rms: Float, frames count: Int, sampleRate rate: Double) {
        sampleRate = rate
        frames += Int64(count)
        if rms.isFinite { peakRMS = max(peakRMS, rms) }
    }

    static func rms(of samples: [Float]) -> Float {
        var value: Float = 0
        vDSP_rmsqv(samples, 1, &value, vDSP_Length(samples.count))
        return value
    }
}
