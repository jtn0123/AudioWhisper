// Random (original, corrected) pairs for CorrectionGateDifferentialTests: dictation
// built from what the correction gate looks for (negation and polarity, digits
// and spoken numbers, flags, emails, paths, code, names, greetings, sign-offs,
// "Subject:" lines), written every way a model might return it (case, curly
// apostrophes, ligatures and expanding case folds, combining marks, decomposed
// letters, emoji, every line break), and corrected the ways a model edits: a
// dropped or flipped negation, a changed digit, an invented greeting, a fix.

struct CorrectionCorpus {
    private var random: TranscriptCorpus

    init(seed: UInt64) { random = TranscriptCorpus(seed: seed) }

    mutating func below(_ bound: Int) -> Int { random.below(bound) }
    mutating func chance(_ bound: Int) -> Bool { random.chance(bound) }
    mutating func pick<T>(_ items: [T]) -> T { random.pick(items) }

    static let negations = [
        "not", "Not", "NOT", "no", "No", "never", "cannot", "unable", "neither", "nor", "dont", "doesnt", "didnt",
        "isnt", "arent", "wasnt", "werent", "havent", "hasnt", "hadnt", "wont", "wouldnt", "shouldnt", "couldnt",
        "mustnt", "cant", "can't", "won’t", "don't", "Isn’t", "DOESN'T", "doeſnt", "muﬆnt", "ﬆill", "n't", "N’T",
        "can’t", "know", "note", "nothing", "x'n't"
    ]

    static let polarity = [
        "negative", "Negative", "minus", "MINUS", "positive", "plus", "Plus", "unless", "without", "WITHOUT",
        "withoutt", "pluses", "ﬁve", "pluß", "MINUß", "unlesß"
    ]

    static let numbers = [
        "5", "42", "125", "1250", "1,250.50", "$125", "$1250", "3pm", "3 PM", "3\nam", "10:30", "10:30am", "-5", "+7",
        "50%", "1.5", "2,000", "٣", "１２", "Ⅻ", "½", "²", "0", "007", "4.2.1", "9,99", "12 %", "5a", "x5", "5_"
    ]

    static let spokenNumbers = [
        "one", "Two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "TWELVE", "zero",
        "hundred", "thousand", "million", "someone", "tenth"
    ]

    static let literals = [
        "-v", "-d", "--force", "--dry-run", "-x_1", "editor@example.com", "owner@example.com", "a.b+c@x-y.io",
        "https://example.com/a?b=c", "http://x.io", "/tmp/report.txt", "/tmp/reports.txt", "~/notes.md", "/",
        "$HOME", "$1", "camelCase", "iPhone", "macOS", "snake_case", "__init__", "a_b", "`grep -v x`", "`code`",
        "`", "app.log", "e.g.", "/usr/bin/env.", "(see /tmp/x)", "über_alles", "fooBär"
    ]

    static let names = [
        "Jordan", "Logan", "Siobhan", "Sarah", "Morgan", "Justin", "Maria", "Alice", "Bob", "O’Brien", "O'Brien",
        "McDonald", "D'Angelo", "José", "Jose\u{301}", "Émile", "E\u{301}mile", "Ǆemal", "ǅ", "Σίσυφος", "İstanbul",
        "I", "So", "Okay", "OK", "Um", "Paris", "Thursday", "Friday", "NASA", "A\u{308}", "Ⓐlpha"
    ]

    static let frames = [
        "Hi", "hi", "Hello", "Hey", "HEY", "Dear", "dear", "Best", "Best regards", "best regards", "Kind regards",
        "Regards", "Sincerely", "Cheers", "[Your Name]", "[your name]", "[Sender]", "[Recipient's name]", "[NAME]",
        "[Your", "[yours truly]", "Subject:", "subject :", "SUBJECT:", "ſubject:", "Subject", "Hi\u{301}", "Hiya",
        "Bestregards", "[name\u{301}]", "[nameſ]", "Hİ", "cheerß"
    ]

    static let plain = [
        "the", "The", "a", "send", "Send", "please", "Please", "delete", "backup", "refund", "approve", "files",
        "upload", "them", "it", "is", "ready", "fine", "release", "to", "and", "but", "like", "actually", "Straße",
        "STRASSE", "ﬁle", "ﬀ", "ǰ", "ᾳ", "\u{0345}", "👍🏽", "🇺🇸", "👨\u{200D}👩", "é", "e\u{301}", "\u{600}x", "ab\u{AD}c"
    ]

    static let separators = [
        " ", " ", " ", " ", "  ", ", ", ". ", "! ", "? ", "\n", "\n\n", "\r\n", "\r", "\t", "\u{85}", "\u{2028}",
        "\u{2029}", "\u{A0}", "\u{200B}", "\u{3000}", ".\n", ",\n\n", "", " - ", ": ", "; "
    ]

    static let marks = [
        ".", ",", "!", "?", ";", ":", ")", "]", "}", "(", "[", "'", "’", "\"", "`", "-", "@", "$", "%", "_", "/",
        "~", "\u{301}", "\u{308}", "\u{200D}", "\u{FE0F}", "\u{903}", "\u{200C}", "\u{2060}", "ﬆ", "ẞ", "ß", "İ"
    ]

    mutating func token() -> String {
        switch below(20) {
        case 0...1: return pick(Self.negations)
        case 2: return pick(Self.polarity)
        case 3...4: return pick(Self.numbers)
        case 5: return pick(Self.spokenNumbers)
        case 6...7: return pick(Self.literals)
        case 8...9: return pick(Self.names)
        case 10: return pick(Self.frames)
        case 11: return pick(Self.marks)
        case 12: return random.scalar()
        default: return pick(Self.plain)
        }
    }

    /// Dictation: tokens and separators, sometimes an email-shaped layout.
    mutating func text(maxTokens: Int = 16) -> String {
        var text = ""
        for index in 0..<below(maxTokens + 1) {
            if index > 0 { text += pick(Self.separators) }
            text += token()
        }
        return chance(6) ? pick(Self.frames) + pick([" ", ",\n\n", "\n", " Sarah,\n"]) + text : text
    }

    /// Lower-case words and spaces only.
    mutating func plain(maxTokens: Int) -> String {
        (0...below(maxTokens)).map { _ in pick(Self.plain).lowercased() }.joined(separator: " ")
    }

    /// The pair a correction model might hand back for `original`.
    mutating func corrected(_ original: String) -> String {
        var tokens = original.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        for _ in 0...below(3) { edit(&tokens) }
        var result = tokens.joined(separator: " ")
        switch below(12) {
        case 0: result = pick(["Hi Sarah,\n\n", "Hello,\n", "Dear Jordan,\n\n", "Subject: Update\n\n", "hey "]) + result
        case 1: result += pick(["\n\nBest regards,\n[Your Name]", "\nCheers", "\n\nKind regards,\nMorgan", "\nThanks"])
        case 2: result = "  " + result + pick(["\n", "  ", "\u{3000}", "\u{200B}", "\u{85}"])
        case 3: result = result.uppercased()
        case 4: result = result.replacingOccurrences(of: "'", with: "’")
        case 5: result = result.decomposedStringWithCanonicalMapping
        case 6: result = result.precomposedStringWithCanonicalMapping
        case 7: result = padded(result, toward: original)
        default: break
        }
        return result
    }

    /// `text`, trimmed and filled out to just under, at or just over a rewrite's length
    /// limit, `max(256, 4 × original.count)` characters.
    private mutating func padded(_ text: String, toward original: String) -> String {
        let limit = max(256, original.count * 4)
        let target = limit + below(3) - 1
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        return trimmed + String(repeating: pick(["x", "é", "👍"]), count: max(0, target - trimmed.count))
    }

    private mutating func edit(_ tokens: inout [String]) {
        guard !tokens.isEmpty else { tokens.append(token()); return }
        let index = below(tokens.count)
        switch below(11) {
        case 0: tokens.remove(at: index)
        case 1: tokens.insert(token(), at: index)
        case 2: tokens[index] = token()
        case 3: tokens[index] = tokens[index].capitalized
        case 4: tokens[index] = tokens[index].lowercased()
        case 5: tokens[index] += pick([",", ".", "?", "!", ":", ")", "]", "}"])
        case 6: tokens[index] = String(tokens[index].map { $0.isNumber ? Character(String(below(10))) : $0 })
        case 7: tokens.insert(pick(["not", "no", "never", "don't", "without", "minus"]), at: index)
        case 8: tokens[index] = tokens[index].replacingOccurrences(of: "n't", with: "")
        case 9: tokens[index] = tokens[index].replacingOccurrences(of: "%", with: pick(["", " percent", " %"]))
        default: break
        }
    }

    /// A long dictation, near the 4,000-character switch to the bounded comparison.
    mutating func long() -> (original: String, corrected: String) {
        // Plain sentences have nothing the integrity check protects, so the length checks decide.
        let plain = chance(2)
        let sentences = (0..<(4 + below(8))).map { _ in
            (plain ? self.plain(maxTokens: 12) : text(maxTokens: 12)) + pick([". ", ".\n", "? ", "\n\n"])
        }
        var original = ""
        let target = pick([3_900, 3_990, 4_000, 4_001, 4_100, 6_000, 12_000])
        while original.count < target { original += pick(sentences) }
        var corrected = original
        switch below(7) {
        case 0: corrected = text(maxTokens: 12) + " " + original
        case 1: corrected = String(original.prefix(original.count / 2 + below(original.count / 2 + 1)))
        case 2: corrected = String((0..<(original.count / 6)).map { _ in pick(["alpha ", "bravo ", "charlie "]) }.joined())
        case 3: corrected = original.replacingOccurrences(of: " the ", with: " a ")
        case 4: corrected = pick([original.uppercased(), original.capitalized])
        // Equal to the original as Swift compares, so the ratio is exactly 0.
        case 5: corrected = original.decomposedStringWithCanonicalMapping
        default: corrected = original + text(maxTokens: 6)
        }
        return chance(3) ? (corrected, original) : (original, corrected)
    }

    /// A pair on one of the bounded comparison's edges.
    mutating func edge() -> (original: String, corrected: String) {
        chance(2) ? budgeted() : doubled()
    }

    /// A long text whose changed span is just under, at or just over the 1,000,000-cell
    /// comparison budget, where the comparison switches from characters to tokens.
    private mutating func budgeted() -> (original: String, corrected: String) {
        let width = pick([800, 1_000, 1_250, 2_000])
        let height = 1_000_000 / width + below(3) - 1
        let prefix = plain(maxTokens: 300), suffix = plain(maxTokens: 300)
        let left = "<" + filler(height - 2) + ">", right = "[" + filler(width - 2) + "]"
        return (prefix + " " + left + " " + suffix, prefix + " " + right + " " + suffix)
    }

    /// Two unrelated texts of about 2,100 characters of two scalars each: over the 4,000 cap
    /// counted in scalars, under it in characters, which is how Swift counts.
    private mutating func doubled() -> (original: String, corrected: String) {
        let make = { (corpus: inout CorrectionCorpus) in
            (0..<(2_050 + corpus.below(100))).map { _ in corpus.pick(["e\u{301}", "o\u{308}", "👍🏽", " "]) }.joined()
        }
        return (make(&self), make(&self))
    }

    private mutating func filler(_ count: Int) -> String {
        String((0..<count).map { _ in pick(Array("abc de")) })
    }

    /// A text either side of the 250,000 UTF-16 unit limit on comparing at all, in short words
    /// (a long run of letters is quadratic for the literal patterns, in the Swift as in the
    /// Rust) and emoji that take two units each, and that text with one character changed.
    mutating func huge() -> (original: String, corrected: String) {
        let unit = pick(["ab ", "😀 ", "é😀 "])
        let target = 249_999 + below(3)
        var original = String(repeating: unit, count: target / unit.utf16.count - 1)
        while original.utf16.count < target { original += "a" }
        let index = original.index(original.startIndex, offsetBy: below(original.count))
        var corrected = original
        corrected.replaceSubrange(index...index, with: pick(["b", "😀a", ""]))
        return chance(2) ? (corrected, original) : (original, corrected)
    }
}
