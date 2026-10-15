import Foundation

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
enum TranscriptFormatter {
    static func format(_ text: String, options: TranscriptFormattingOptions) -> String {
        guard !options.isIdentity else { return text }
        var result = text
        if options.spokenPunctuation { result = applySpokenPunctuation(result) }
        if options.removeFillers { result = removeFillers(result) }
        result = options.vocabulary.apply(to: result)
        return result
    }

    // MARK: Spoken punctuation

    private struct Command {
        let words: [String]
        let symbol: String
        /// "period" is an ordinary noun ("a period of time"), so it only acts
        /// as a command where a sentence could end.
        var needsSentenceEnd = false
    }

    private static let commands: [Command] = [
        Command(words: ["new paragraph"], symbol: "\n\n"),
        Command(words: ["new line", "newline"], symbol: "\n"),
        Command(words: ["question mark"], symbol: "?"),
        Command(words: ["exclamation mark", "exclamation point"], symbol: "!"),
        Command(words: ["full stop", "period"], symbol: ".", needsSentenceEnd: true),
        Command(words: ["semicolon", "semi colon"], symbol: ";"),
        Command(words: ["colon"], symbol: ":"),
        Command(words: ["comma"], symbol: ",")
    ]

    /// Marks where a new sentence begins after a rewrite; see `capitalizeMarked`.
    private static let sentenceMark = "\u{E000}"

    /// "Hi comma how are you question mark" → "Hi, how are you?". Whisper often
    /// punctuates around the spoken word too ("Hi, comma, how"), so adjacent
    /// marks are absorbed into the command.
    static func applySpokenPunctuation(_ text: String) -> String {
        var result = text
        for command in commands {
            let words = command.words.map { $0.replacingOccurrences(of: " ", with: "\\s+") }.joined(separator: "|")
            let isBreak = command.symbol.hasPrefix("\n")
            var pattern = "[ \\t]*[,.;:!?]*[ \\t]*(?<![\\p{L}\\p{N}_])(?i:\(words))(?![\\p{L}\\p{N}_])"
            pattern += isBreak ? "[,.;:!?]*[ \\t]*" : "[,.;:!?]*"
            if command.needsSentenceEnd { pattern += "(?=[ \\t]*$|[ \\t]+\\p{Lu}|[ \\t]*\\n)" }
            let endsSentence = isBreak || ".?!".contains(command.symbol)
            let template = NSRegularExpression.escapedTemplate(for: command.symbol) + (endsSentence ? sentenceMark : "")
            // Case-insensitivity stays scoped to the words; a global flag would
            // let the sentence-end lookahead's \p{Lu} match lowercase too.
            result = replace(pattern, in: result, with: template, options: [.anchorsMatchLines])
        }
        return capitalizeMarked(result).trimmingCharacters(in: .whitespaces)
    }

    // MARK: Filler words

    /// "uh" and "uhm" are never words, so they go wherever they appear. "um" is
    /// a real word in German ("um 5 Uhr") and Portuguese ("um carro"), so it is
    /// removed only when punctuated as an interjection: "Um, so" / "so, um, I".
    static func removeFillers(_ text: String) -> String {
        let start = "(?<![\\p{L}\\p{N}_'’-])"
        let end = "(?![\\p{L}\\p{N}_'’-])"
        let always = "(?:uh+m*|umm+|erm+)"
        let any = "(?:uh+m*|umm+|erm+|um)"
        // A filler that opens a sentence hands its capital to the next word.
        var result = replace(
            "(^|[.!?][ \\t]+)\(start)(?:\(always)|um(?=[,.…]))\(end)[,.…]*[ \\t]*", in: text,
            with: "$1" + sentenceMark, options: [.caseInsensitive, .anchorsMatchLines])
        // Commas that only bracketed the filler go with it: "I was, uh, thinking".
        result = replace("[ \\t]*,[ \\t]*\(start)\(any)\(end)[ \\t]*,", in: result, with: "", options: [.caseInsensitive])
        result = replace("[ \\t]*,[ \\t]*\(start)\(any)\(end)(?=[.!?…])", in: result, with: "", options: [.caseInsensitive])
        // A comma the speaker dictated before an unbracketed filler stays.
        result = replace("[ \\t]*\(start)\(always)\(end)[,…]?", in: result, with: "", options: [.caseInsensitive])
        return tidy(capitalizeMarked(result))
    }

    // MARK: Helpers

    /// Collapses the gaps a removal leaves: doubled spaces, a space before
    /// punctuation, a doubled comma, a comma left at the very start.
    static func tidy(_ text: String) -> String {
        var result = replace("[ \\t]{2,}", in: text, with: " ")
        result = replace("[ \\t]+([,.;:!?])", in: result, with: "$1")
        result = replace(",{2,}", in: result, with: ",")
        result = replace("^[ \\t]*[,;:][ \\t]*", in: result, with: "", options: [.anchorsMatchLines])
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Uppercases the all-lowercase word after each sentence mark, then drops
    /// the marks. Only positions a rule rewrote are touched, so existing text
    /// such as "e.g. this" keeps its case; a word with an internal capital
    /// ("iPhone") is left alone.
    static func capitalizeMarked(_ text: String) -> String {
        var result = text
        let pattern = sentenceMark + "([ \\t\\n]*)(\\p{Ll}[\\p{Ll}'’]*)(?![\\p{L}])"
        if let regex = try? NSRegularExpression(pattern: pattern) {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed() {
                guard let range = Range(match.range(at: 2), in: result) else { continue }
                let word = result[range]
                result.replaceSubrange(range, with: word.prefix(1).uppercased() + word.dropFirst())
            }
        }
        return result.replacingOccurrences(of: sentenceMark, with: "")
    }

    static func replace(
        _ pattern: String, in text: String, with template: String, options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..<text.endIndex, in: text), withTemplate: template)
    }
}
