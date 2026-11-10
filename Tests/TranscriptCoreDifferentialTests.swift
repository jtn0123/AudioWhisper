import XCTest
@testable import AudioWhisper

/// Holds the transcript rules, now in Rust (Vendor/AudioWhisper-Core), to the
/// Swift they were ported from (Tests/Reference), on random dictation-like text.
///
/// Comparison is scalar for scalar: canonical equivalence would hide a real
/// difference, such as a decomposed "é" coming back composed. Both sides run on
/// this Mac's Unicode data, so this also catches a macOS update that changes
/// ICU or Foundation in a way the core's generated tables don't follow
/// (regenerate them with the core's tools/unicode-tables.sh).
final class TranscriptCoreDifferentialTests: XCTestCase {
    private static let cases = 1500
    /// Differences shown per test; one broken rule would otherwise report hundreds.
    private static let shownDifferences = 5
    private var differences = 0

    func testSpokenPunctuationAndFillersMatchTheSwift() {
        var corpus = TranscriptCorpus(seed: 1)
        for _ in 0..<Self.cases {
            let text = corpus.text()
            assertSame(TranscriptFormatter.applySpokenPunctuation(text),
                       ReferenceTranscriptFormatter.applySpokenPunctuation(text), "spoken", text)
            assertSame(TranscriptFormatter.removeFillers(text),
                       ReferenceTranscriptFormatter.removeFillers(text), "fillers", text)
        }
    }

    func testFitMatchesTheSwift() {
        var corpus = TranscriptCorpus(seed: 2)
        for _ in 0..<Self.cases {
            let text = corpus.text()
            let preceding = corpus.chance(8) ? nil : corpus.text(maxTokens: 5)
            assertSame(CursorContextFormatter.fit(text, after: preceding),
                       ReferenceCursorContextFormatter.fit(text, after: preceding), "fit", "\(text) after \(preceding ?? "nil")")
            let focused = corpus.cursorContext()
            assertSame(CursorContextFormatter.fit(focused.text, after: focused.preceding),
                       ReferenceCursorContextFormatter.fit(focused.text, after: focused.preceding),
                       "fit", "\(focused.text) after \(focused.preceding)")
        }
    }

    func testParsingAndPromptMatchTheSwift() {
        var corpus = TranscriptCorpus(seed: 3)
        for _ in 0..<Self.cases {
            let source = corpus.vocabularySource()
            let vocabulary = CustomVocabulary(parsing: source)
            let reference = ReferenceCustomVocabulary(parsing: source)
            assertSame(describe(vocabulary), describe(reference), "parse", source)
            assertSame(vocabulary.promptText, reference.promptText, "prompt", source)
        }
    }

    func testApplyingAndFormattingMatchTheSwift() {
        var corpus = TranscriptCorpus(seed: 4)
        for _ in 0..<Self.cases {
            let text = corpus.text()
            let source = corpus.vocabularySource()
            let vocabulary = CustomVocabulary(parsing: source)
            let reference = ReferenceCustomVocabulary(parsing: source)
            assertSame(vocabulary.apply(to: text), reference.apply(to: text), "apply", "\(text) with \(source)")
            assertFormatsAlike(text, vocabulary, reference, &corpus)
        }
    }

    func testVocabulariesBuiltInCodeMatchTheSwift() {
        var corpus = TranscriptCorpus(seed: 5)
        for _ in 0..<Self.cases {
            let pick = { (corpus: inout TranscriptCorpus) in
                corpus.chance(2) ? corpus.pick(TranscriptCorpus.oddTerms) : corpus.text(maxTokens: 2)
            }
            let terms = (0..<corpus.below(3)).map { _ in pick(&corpus) }
            let pairs = (0..<corpus.below(3)).map { _ in (pick(&corpus), corpus.text(maxTokens: 2)) }
            let (vocabulary, reference) = both(terms, pairs)
            let text = corpus.text() + (corpus.chance(2) ? "" : " \(corpus.pick(TranscriptCorpus.oddTerms)) \(corpus.text(maxTokens: 4))")
            assertSame(vocabulary.apply(to: text), reference.apply(to: text), "direct", "\(text) with \(terms) \(pairs)")
            assertSame(vocabulary.promptText, reference.promptText, "direct prompt", "\(terms) \(pairs)")
        }
    }

    func testLongVocabulariesAndDictationMatchTheSwift() {
        var corpus = TranscriptCorpus(seed: 6)
        for _ in 0..<(Self.cases / 20) {
            let terms = (0..<(20 + corpus.below(120))).map { _ in
                corpus.pick(TranscriptCorpus.words) + corpus.text(maxTokens: 2)
            }
            let (vocabulary, reference) = both(terms, [])
            assertSame(vocabulary.promptText, reference.promptText, "long prompt", "\(terms.count) terms")
            let separator = corpus.pick([" ", ". ", ", ", "\n"])
            let text = (0..<40).map { _ in corpus.text(maxTokens: 12) }.joined(separator: separator)
            assertFormatsAlike(text, vocabulary, reference, &corpus)
        }
    }

    func testCamelCasePartsMatchTheSwift() {
        var corpus = TranscriptCorpus(seed: 7)
        for _ in 0..<Self.cases {
            let term = corpus.text(maxTokens: 4)
            assertSame("\(CustomVocabulary.camelCaseParts(of: term))",
                       "\(ReferenceCustomVocabulary.camelCaseParts(of: term))", "camel case", term)
        }
    }

    // MARK: Helpers

    private func assertFormatsAlike(
        _ text: String, _ vocabulary: CustomVocabulary, _ reference: ReferenceCustomVocabulary,
        _ corpus: inout TranscriptCorpus
    ) {
        let fillers = corpus.chance(2), spoken = corpus.chance(2)
        let options = TranscriptFormattingOptions(vocabulary: vocabulary, removeFillers: fillers, spokenPunctuation: spoken)
        let referenceOptions = ReferenceFormattingOptions(
            vocabulary: reference, removeFillers: fillers, spokenPunctuation: spoken)
        assertSame(TranscriptFormatter.format(text, options: options),
                   ReferenceTranscriptFormatter.format(text, options: referenceOptions),
                   "format", "\(text) fillers \(fillers) spoken \(spoken)")
    }

    private func both(
        _ terms: [String], _ pairs: [(String, String)]
    ) -> (CustomVocabulary, ReferenceCustomVocabulary) {
        (CustomVocabulary(terms: terms, replacements: pairs.map { .init(heard: $0.0, written: $0.1) }),
         ReferenceCustomVocabulary(terms: terms, replacements: pairs.map { .init(heard: $0.0, written: $0.1) }))
    }

    private func describe(_ vocabulary: CustomVocabulary) -> String {
        "\(vocabulary.terms) \(vocabulary.replacements.map { [$0.heard, $0.written] })"
    }

    private func describe(_ vocabulary: ReferenceCustomVocabulary) -> String {
        "\(vocabulary.terms) \(vocabulary.replacements.map { [$0.heard, $0.written] })"
    }

    private func assertSame(
        _ rust: String?, _ swift: String?, _ rule: String, _ input: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard rust.map({ Array($0.unicodeScalars) }) != swift.map({ Array($0.unicodeScalars) }) else { return }
        differences += 1
        guard differences <= Self.shownDifferences else { return }
        XCTFail("\(rule) differs for \(escaped(input)):\n  rust  \(escaped(rust))\n  swift \(escaped(swift))",
                file: file, line: line)
    }

    private func escaped(_ text: String?) -> String {
        guard let text else { return "nil" }
        return "\"" + text.unicodeScalars.map { scalar in
            scalar.isASCII && scalar.value >= 0x20 ? String(scalar) : "\\u{\(String(scalar.value, radix: 16))}"
        }.joined() + "\""
    }
}
