import Foundation

/// The user's words: spellings to enforce and phrases to rewrite.
///
/// Edited as plain text, one entry per line:
///
///     Kubernetes
///     AudioWhisper
///     post gress -> Postgres
///
/// A bare line is a *term*: any case-insensitive whole-word match is rewritten
/// to that exact spelling, and a CamelCase term also matches its spoken split
/// ("audio whisper" → "AudioWhisper"). Terms also bias WhisperKit through its
/// decoder prompt. A `heard -> written` (or `=>`) line is a *replacement*.
/// Blank lines and lines starting with `#` are ignored.
struct CustomVocabulary: Equatable, Sendable {
    struct Replacement: Equatable, Sendable {
        let heard: String
        let written: String
    }

    /// Whisper's prompt window is 224 tokens and is shared with the decoder
    /// context, so the prompt stays well under it.
    static let maxPromptCharacters = 400

    private(set) var terms: [String] = []
    private(set) var replacements: [Replacement] = []

    static let empty = Self()

    var isEmpty: Bool { terms.isEmpty && replacements.isEmpty }

    init(terms: [String] = [], replacements: [Replacement] = []) {
        self.terms = terms
        self.replacements = replacements
    }

    init(parsing text: String) {
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if let arrow = line.range(of: "->") ?? line.range(of: "=>") {
                let heard = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
                let written = line[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
                guard !heard.isEmpty else { continue }
                replacements.append(Replacement(heard: heard, written: written))
            } else if !terms.contains(line) {
                terms.append(line)
            }
        }
    }

    /// Spellings WhisperKit should lean toward, as a natural comma list. Only
    /// the leading entries that fit `maxPromptCharacters` are used.
    var promptText: String? {
        let spellings = terms + replacements.map(\.written).filter { !$0.isEmpty }
        var prompt = ""
        var seen: Set<String> = []
        for spelling in spellings where seen.insert(spelling).inserted {
            let next = prompt.isEmpty ? spelling : prompt + ", " + spelling
            guard next.count <= Self.maxPromptCharacters else { break }
            prompt = next
        }
        return prompt.isEmpty ? nil : prompt
    }

    /// Replacements first, so a rewrite can produce a term's spelling; terms
    /// then normalise case and spoken CamelCase splits.
    func apply(to text: String) -> String {
        var result = text
        for replacement in replacements {
            result = Self.replaceWholePhrase(replacement.heard, with: replacement.written, in: result)
        }
        for term in terms {
            result = Self.replaceWholePhrase(term, with: term, in: result, matchingSplitCamelCase: true)
        }
        return result
    }

    static func replaceWholePhrase(
        _ phrase: String, with replacement: String, in text: String, matchingSplitCamelCase: Bool = false
    ) -> String {
        let words = matchingSplitCamelCase ? camelCaseParts(of: phrase) : [phrase]
        let body = words.map { part in
            part.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: "\\s+")
        }.joined(separator: "[\\s-]?")
        let pattern = "(?<![\\p{L}\\p{N}_])" + body + "(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(
            in: text, range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    /// "AudioWhisper" → ["Audio", "Whisper"]; "PostgreSQL" → ["Postgre", "SQL"].
    /// A lowercase→uppercase step starts a new part; acronym runs stay whole.
    static func camelCaseParts(of term: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var previous: Character?
        for character in term {
            if let previous, previous.isLowercase, character.isUppercase, !current.isEmpty {
                parts.append(current)
                current = ""
            }
            current.append(character)
            previous = character
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
