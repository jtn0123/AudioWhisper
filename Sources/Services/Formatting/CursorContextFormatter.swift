import Foundation

/// Fits a transcript to the text it is inserted after: a space so words do not
/// run together, and the first word's case matched to whether the insertion
/// starts or continues a sentence.
///
/// Both engines capitalise the first word of every transcript, which is wrong
/// mid-sentence. Lowercasing is limited to common function words, so a name
/// ("Paris", "Justin") or anything outside English keeps its capital.
enum CursorContextFormatter {
    static func fit(_ text: String, after preceding: String?) -> String {
        guard let preceding, let first = text.first, !first.isWhitespace else { return text }
        let trimmedBefore = preceding.trimmingCharacters(in: .whitespaces)
        var result = text
        if trimmedBefore.isEmpty || trimmedBefore.last?.isNewline == true || endsSentence(trimmedBefore) {
            result = capitalizingFirstWord(result)
        } else if continuesSentence(trimmedBefore) {
            result = lowercasingFirstWord(result)
        }
        return needsSpace(after: preceding, before: result) ? " " + result : result
    }

    private static let sentenceEnders: Set<Character> = [".", "!", "?", "…"]
    private static let openers: Set<Character> = ["(", "[", "{", "\"", "'", "“", "‘", "«", "/", "@", "#", "$"]
    private static let attachesLeft: Set<Character> = [",", ".", ";", ":", "!", "?", ")", "]", "}", "…", "'", "’", "%"]

    private static func endsSentence(_ text: String) -> Bool {
        var trimmed = Substring(text)
        // A sentence can end inside a closing quote or bracket: `He left.")`
        while let last = trimmed.last, "\"'”’)]".contains(last) { trimmed = trimmed.dropLast() }
        return trimmed.last.map(sentenceEnders.contains) ?? false
    }

    private static func continuesSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return last.isLetter || last.isNumber || ",;:-–—".contains(last)
    }

    private static func needsSpace(after preceding: String, before text: String) -> Bool {
        guard let last = preceding.last, let first = text.first else { return false }
        return !last.isWhitespace && !isOpening(last, in: preceding) && !attachesLeft.contains(first)
    }

    /// A straight quote opens only at the start or after a space; `said "stop."`
    /// ends with a closing one.
    private static func isOpening(_ last: Character, in preceding: String) -> Bool {
        guard openers.contains(last) else { return false }
        guard last == "\"" || last == "'" else { return true }
        return preceding.dropLast().last.map(\.isWhitespace) ?? true
    }

    private static func capitalizingFirstWord(_ text: String) -> String {
        let word = firstWord(of: text)
        guard !word.isEmpty, word.allSatisfy({ !$0.isUppercase }), word.first?.isLowercase == true else { return text }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private static func lowercasingFirstWord(_ text: String) -> String {
        let word = firstWord(of: text)
        let key = word.lowercased().replacingOccurrences(of: "’", with: "'")
        guard word.dropFirst().allSatisfy({ !$0.isUppercase }), continuationWords.contains(key) else { return text }
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    private static func firstWord(of text: String) -> Substring {
        text.prefix { $0.isLetter || $0 == "'" || $0 == "’" }
    }

    /// Words that capitalise only because they open a transcript. "I" and its
    /// contractions are absent on purpose.
    private static let continuationWords: Set<String> = [
        "a", "about", "after", "again", "all", "also", "an", "and", "any", "are", "as", "at", "because",
        "been", "before", "but", "by", "can", "could", "did", "do", "does", "each", "even", "every", "for",
        "from", "had", "has", "have", "he", "her", "here", "his", "how", "if", "in", "into", "is", "it",
        "it's", "its", "just", "let's", "like", "maybe", "more", "most", "my", "no", "not", "now", "of",
        "on", "one", "only", "or", "our", "she", "should", "so", "some", "than", "that", "that's", "the",
        "their", "them", "then", "there", "there's", "these", "they", "they're", "this", "those", "though",
        "to", "too", "until", "was", "we", "we're", "were", "what", "when", "where", "which", "while", "who",
        "why", "will", "with", "would", "yes", "yet", "you", "you're", "your"
    ]
}
