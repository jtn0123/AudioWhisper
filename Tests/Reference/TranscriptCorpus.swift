// Random dictation-like text for TranscriptCoreDifferentialTests: the words the
// rules react to, written every way a recogniser or a user might (case,
// spacing, ligatures, combining marks, characters whose case folding expands),
// mixed with every kind of whitespace and line break and random scalars.

import Foundation

/// SplitMix64: seeded, so a failure reproduces.
struct TranscriptCorpus {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    mutating func chance(_ bound: Int) -> Bool { below(bound) == 0 }
    mutating func pick<T>(_ items: [T]) -> T { items[below(items.count)] }

    static let words = [
        "comma", "Comma", "COMMA", "period", "Period", "full stop", "full  stop", "new line", "newline",
        "New Line", "new paragraph", "question mark", "exclamation mark", "exclamation point", "semicolon",
        "semi colon", "colon", "uh", "Uh", "uhh", "uhm", "UHM", "um", "Um", "umm", "erm", "Erm", "ermm",
        "hello", "World", "iPhone", "audio", "Audio", "whisper", "AudioWhisper", "audio-whisper", "post", "gress",
        "Postgres", "PostgreSQL", "postgre", "sql", "e.g.", "Straße", "STRASSE", "strasse", "ß", "ﬅ", "ſ",
        "\u{212A}", "k", "the", "The", "and", "And", "It's", "it’s", "Let’s", "I", "Paris", "you're", "So", "so",
        "a", "A", "ǅ", "ǆ", "Σ", "ς", "σ", "ŉ", "İ", "ı", "ﬁ", "ﬁle", "Ǳ", "ɐ", "Ꞵ", "ꞵ", "ǈ", "é", "e\u{301}",
        "É", "E\u{301}", "一", "二", "百", "5", "42", "Ⅻ", "½", "٣", "x", "Kubernetes", "kubernetes", "ok", "OK",
        "Um.", "uh,", "\u{E000}", "\u{F8FF}", "👍🏽", "🇺🇸", "\u{0345}", "a\u{0345}", "ᾳ", "ǰ", "ﬀ", "Ⓐ", "ⓐ"
    ]

    static let separators = [
        " ", " ", " ", " ", "  ", "\t", "\n", "\n\n", "\r\n", "\r", "\u{85}", "\u{2028}", "\u{2029}",
        "\u{0B}", "\u{0C}", "\u{A0}", "\u{3000}", "\u{200B}", "\u{2009}", "\u{202F}", "\u{1680}", ""
    ]

    static let marks = [
        ",", ".", "!", "?", ";", ":", "…", "'", "’", "-", "–", "—", "\"", "“", "”", "‘", "(", ")", "[", "]",
        "{", "}", "«", "/", "@", "#", "$", "%", "_", "->", "=>", "\u{301}", "\u{308}", "\u{200D}", ",,", "..",
        "-\u{301}", ">\u{301}", "\u{600}", "\u{110BD}", "\u{FE0F}", "\u{1F3FD}", "\u{0903}", "ẞ", "ﬆ",
        "\u{1E96}", "\u{0130}", "#\u{301}", ".\u{301}", "’\u{301}", "'\u{301}", "\"\u{301}"
    ]

    /// Terms a vocabulary built in code can hold but parsing never produces.
    static let oddTerms = [
        "", " ", "\u{0}", "ss", "sssssssssssssssssssssssss", "ßß", "SS", "ẞ", "a B", " x", "Ab-Cd", "\u{345}",
        "İ", "ﬆ"
    ]

    private static let scalarRanges: [ClosedRange<UInt32>] = [
        0x20...0x7E, 0xA0...0x24F, 0x370...0x3FF, 0x400...0x4FF, 0x1E00...0x1FFF, 0x2000...0x206F,
        0x2100...0x218F, 0x300...0x36F, 0x3000...0x30FF, 0x4E00...0x4E20, 0xAC00...0xAC10, 0x1F300...0x1F3FF,
        0x10400...0x1044F, 0x1E900...0x1E95F, 0x0...0x1F, 0xE000...0xE002, 0xFB00...0xFB4F, 0xA7C0...0xA7FF,
        0x16EA0...0x16EDF, 0x31350...0x31360, 0xF880...0xF8FF, 0x88F...0x88F, 0x11DE0...0x11DEF,
        0x1E9E...0x1E9E, 0x10D40...0x10D8F
    ]

    /// A random scalar this macOS has assigned. The core's tables are Unicode
    /// 17, but the reference Swift runs on whatever ICU and Swift the machine
    /// has (macOS 15 has Unicode 15.1), so a character added later is a
    /// letter to the core and unknown to an older system. That difference is
    /// the core being newer, not a port mistake (ADR 0007), so such a
    /// character is drawn again.
    mutating func scalar() -> String {
        while true {
            let range = pick(Self.scalarRanges)
            let value = range.lowerBound + UInt32(below(Int(range.upperBound - range.lowerBound + 1)))
            guard let scalar = Unicode.Scalar(value) else { return "?" }
            let text = String(Character(scalar))
            if Self.isAssigned(scalar, text) { return text }
        }
    }

    /// Whether both the Swift standard library and ICU on this machine know
    /// `scalar`. Private-use characters count as assigned.
    private static func isAssigned(_ scalar: Unicode.Scalar, _ text: String) -> Bool {
        scalar.properties.generalCategory != .unassigned
            && text.range(of: "\\p{Cn}", options: .regularExpression) == nil
    }

    mutating func text(maxTokens: Int = 14) -> String {
        var text = ""
        for _ in 0..<below(maxTokens + 1) {
            switch below(10) {
            case 0...3: text += pick(Self.words)
            case 4...6: text += pick(Self.separators)
            case 7...8: text += pick(Self.marks)
            default: text += scalar()
            }
        }
        return text
    }

    /// A vocabulary as a user writes it: terms, replacements, comments, and
    /// every kind of line break between them.
    mutating func vocabularySource() -> String {
        var source = ""
        for _ in 0..<below(5) {
            switch below(4) {
            case 0: source += text(maxTokens: 3) + pick([" -> ", "->", " => ", "=>"]) + text(maxTokens: 3)
            case 1: source += pick(["#", " # ", ""]) + text(maxTokens: 3)
            default: source += pick(Self.words) + (chance(3) ? pick(Self.words) : "")
            }
            source += pick(["\n", "\r\n", "\u{2028}", "\u{85}", "\n\n", "\r", "\u{0B}"])
        }
        return source
    }

    /// Text before the cursor, built from what `fit` looks at: sentence ends,
    /// closing quotes and brackets, openers and spaces.
    mutating func cursorContext() -> (text: String, preceding: String) {
        let tails = [
            ".", "!", "?", "…", "\"", "'", "”", "’", ")", "]", " ", "  ", "(", "[", ",", ";", "-", "—", "\n", "\t",
            "\u{A0}", "\u{200B}", "“", "«", "@", "5", "\u{301}"
        ]
        let starts = [
            "we go", "We go", "the end", "Paris", "It's", "It’s", "and", "iPhone", ", more", "\"quote", "it’s",
            "I agree", "NASA", "ǅemal", "élan", "Élan", "SO", "So", "Let’s", "e\u{301}tait", " lead", ""
        ]
        let preceding = (chance(3) ? "" : pick(Self.words)) + (0..<below(4)).map { _ in pick(tails) }.joined()
        return (pick(starts) + (chance(3) ? pick(tails) : ""), preceding)
    }
}
