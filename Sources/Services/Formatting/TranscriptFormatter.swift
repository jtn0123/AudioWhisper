import CAWCore

/// The deterministic text stage between recognition and optional cleanup.
/// Captured with the rest of the pipeline settings when a session starts, so a
/// retry formats exactly as the original attempt would have.
struct TranscriptFormattingOptions: Equatable, Sendable {
    var vocabulary: CustomVocabulary = .empty
    var removeFillers = false
    var spokenPunctuation = false

    static let none = Self()

    var isIdentity: Bool { vocabulary.isEmpty && !removeFillers && !spokenPunctuation }

    static var current: Self {
        Self(
            vocabulary: CustomVocabulary(parsing: AppDefaults.customVocabulary),
            removeFillers: AppDefaults.removeFillerWords,
            spokenPunctuation: AppDefaults.spokenPunctuation)
    }
}

/// Rule-based formatting that both engines share. Every rule is conservative:
/// it rewrites only text that cannot plausibly be meant literally, because a
/// wrong rewrite is pasted straight into someone's document.
///
/// The rules run in Rust (`transcript::formatter`, through `TranscriptCore`).
enum TranscriptFormatter {
    static func format(_ text: String, options: TranscriptFormattingOptions) -> String {
        guard !options.isIdentity else { return text }
        return TranscriptCore.withVocabulary(options.vocabulary) { vocabulary in
            TranscriptCore.transform(text) {
                aw_format($0, $1, vocabulary, options.removeFillers, options.spokenPunctuation)
            }
        }
    }

    /// "Hi comma how are you question mark" → "Hi, how are you?". Whisper often
    /// punctuates around the spoken word too ("Hi, comma, how"), so adjacent
    /// marks are absorbed into the command. "period" is an ordinary noun ("a
    /// period of time"), so it only acts as a command where a sentence could end.
    static func applySpokenPunctuation(_ text: String) -> String {
        TranscriptCore.transform(text) { aw_spoken_punctuation($0, $1) }
    }

    /// "uh" and "uhm" are never words, so they go wherever they appear. "um" is
    /// a real word in German ("um 5 Uhr") and Portuguese ("um carro"), so it is
    /// removed only when punctuated as an interjection: "Um, so" / "so, um, I".
    static func removeFillers(_ text: String) -> String {
        TranscriptCore.transform(text) { aw_remove_fillers($0, $1) }
    }
}
