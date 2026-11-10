import XCTest
@testable import AudioWhisper

/// Holds the correction gate, now in Rust (Vendor/AudioWhisper-Core), to the
/// Swift it was ported from (Tests/Reference), on random dictation and the
/// corrections a model might return for it.
///
/// Texts compare scalar for scalar and ratios bit for bit: canonical
/// equivalence would hide a decomposed "é" coming back composed, and a ratio
/// that differs in its last bit can still land on the other side of a limit.
/// Both sides run on this Mac's ICU and Unicode data, so this also catches a
/// macOS update the core's generated tables don't follow (regenerate them with
/// the core's tools/unicode-tables.sh).
final class CorrectionGateDifferentialTests: XCTestCase {
    private static let cases = 500
    private static let longCases = 6
    private static let edgeCases = 2
    /// Differences shown per test; one broken rule would otherwise report hundreds.
    private static let shownDifferences = 5
    private var differences = 0

    func testTheConstantsMatchTheSwift() {
        XCTAssertEqual(SemanticCorrectionService.maxChangeRatio, ReferenceSemanticCorrection.maxChangeRatio)
        XCTAssertEqual(SemanticCorrectionService.safeMergeLengthCap, ReferenceSemanticCorrection.safeMergeLengthCap)
    }

    func testTheIntegrityCheckMatchesTheSwift() {
        var corpus = CorrectionCorpus(seed: 11)
        for index in 0..<Self.cases {
            let (original, corrected) = pair(&corpus, index)
            for framing in [false, true] {
                assertSame(
                    "\(CorrectionIntegrity.allows(original: original, corrected: corrected, allowFraming: framing))",
                    "\(ReferenceCorrectionIntegrity.allows(original: original, corrected: corrected, allowFraming: framing))",
                    "allows framing \(framing)", original, corrected)
            }
        }
    }

    func testTheRatiosMatchTheSwift() {
        var corpus = CorrectionCorpus(seed: 12)
        for index in 0..<Self.cases {
            let (original, corrected) = pair(&corpus, index)
            assertRatiosMatch(original, corrected)
        }
    }

    func testMergingAndAcceptingMatchTheSwift() {
        var corpus = CorrectionCorpus(seed: 13)
        for index in 0..<Self.cases {
            let (original, corrected) = pair(&corpus, index)
            assertMergesMatch(original, corrected, &corpus)
        }
    }

    /// Texts either side of the 4,000-character switch to the bounded comparison.
    /// The distance isn't compared on its own: the Swift's quadratic DP takes over a
    /// second a case, and under the switch `safeMerge` computes it anyway.
    func testLongDictationMatchesTheSwift() {
        var corpus = CorrectionCorpus(seed: 14)
        for _ in 0..<Self.longCases {
            let (original, corrected) = corpus.long()
            assertRatiosMatch(original, corrected, distance: false)
            assertMergesMatch(original, corrected, &corpus)
        }
    }

    /// Changed spans at the comparison budget, and texts over the length cap in scalars but
    /// not in characters.
    func testTheBoundedComparisonsEdgesMatchTheSwift() {
        var corpus = CorrectionCorpus(seed: 15)
        for _ in 0..<Self.edgeCases {
            let (original, corrected) = corpus.edge()
            assertRatiosMatch(original, corrected, distance: false)
            assertMergesMatch(original, corrected, &corpus)
        }
    }

    // MARK: Helpers

    /// A random dictation and, mostly, a model's edit of it; sometimes an unrelated text.
    private func pair(_ corpus: inout CorrectionCorpus, _ index: Int) -> (String, String) {
        let original = corpus.text()
        return (original, index % 5 == 0 ? corpus.text() : corpus.corrected(original))
    }

    private func assertRatiosMatch(_ original: String, _ corrected: String, distance: Bool = true) {
        assertSame(bits(CorrectionContentComparison.ratio(original: original, corrected: corrected)),
                   bits(ReferenceCorrectionContentComparison.ratio(original: original, corrected: corrected)),
                   "ratio", original, corrected)
        guard distance else { return }
        assertSame(bits(SemanticCorrectionService.normalizedEditDistance(a: original, b: corrected)),
                   bits(ReferenceSemanticCorrection.normalizedEditDistance(a: original, b: corrected)),
                   "distance", original, corrected)
    }

    private func assertMergesMatch(_ original: String, _ corrected: String, _ corpus: inout CorrectionCorpus) {
        let limit = corpus.pick([0, 0.2, 0.25, 0.3, 0.6, 0.85, 1, Double(corpus.below(1000)) / 997, .nan, .infinity])
        assertSame(SemanticCorrectionService.safeMerge(original: original, corrected: corrected, maxChangeRatio: limit),
                   ReferenceSemanticCorrection.safeMerge(original: original, corrected: corrected, maxChangeRatio: limit),
                   "safeMerge limit \(limit)", original, corrected)
        for operation in WritingOperation.allCases {
            assertSame(DictationWriting(operation: operation).accepted(original: original, output: corrected),
                       ReferenceDictationWriting(operation: operation).accepted(original: original, output: corrected),
                       "accepted \(operation)", original, corrected)
        }
    }

    private func bits(_ value: Double?) -> String {
        value.map { String($0.bitPattern, radix: 16) } ?? "nil"
    }

    private func assertSame(
        _ rust: String, _ swift: String, _ rule: String, _ original: String, _ corrected: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard Array(rust.unicodeScalars) != Array(swift.unicodeScalars) else { return }
        differences += 1
        guard differences <= Self.shownDifferences else { return }
        XCTFail("""
            \(rule) differs for \(escaped(original)) corrected to \(escaped(corrected)):
              rust  \(escaped(rust))
              swift \(escaped(swift))
            """, file: file, line: line)
    }

    private func escaped(_ text: String) -> String {
        let scalars = text.unicodeScalars
        let shown = scalars.count > 400 ? String(String.UnicodeScalarView(scalars.prefix(400))) + "…" : text
        return "\"" + shown.unicodeScalars.map { scalar in
            scalar.isASCII && scalar.value >= 0x20 ? String(scalar) : "\\u{\(String(scalar.value, radix: 16))}"
        }.joined() + "\""
    }
}
