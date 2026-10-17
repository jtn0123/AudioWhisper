import XCTest
@testable import AudioWhisper

final class RebuildVocabularyDocumentTests: XCTestCase {
    func testEditingAndRemovingPreserveEverySupportedLineSeparator() throws {
        for separator in ["\n", "\r", "\r\n", "\u{000B}", "\u{000C}", "\u{0085}", "\u{2028}", "\u{2029}"] {
            let source = "# Keep this note\(separator)Alpha\(separator)Beta\(separator)"
            let document = RebuildVocabularyDocument(source: source)
            XCTAssertEqual(document.entries.count, CustomVocabulary(parsing: source).terms.count)
            let entry = try XCTUnwrap(document.matching("Alpha").first)
            var draft = RebuildVocabularyDocument.Draft(entry: entry)
            draft.written = "Changed"
            XCTAssertEqual(try document.saving(draft), source.replacingOccurrences(of: "Alpha", with: "Changed"))
            XCTAssertEqual(try document.removing(entry), "# Keep this note\(separator)Beta\(separator)")
            let last = try XCTUnwrap(RebuildVocabularyDocument(source: "Alpha\(separator)Beta").matching("Beta").first)
            XCTAssertEqual(try RebuildVocabularyDocument(source: "Alpha\(separator)Beta").removing(last), "Alpha")
        }
    }

    func testWordEntryIgnoresAnInvalidHiddenHeardPhrase() throws {
        var draft = RebuildVocabularyDocument.Draft()
        draft.written = "SwiftUI"
        for hidden in ["# Hidden", "one -> two", "one\ntwo"] {
            draft.heard = hidden
            XCTAssertEqual(try RebuildVocabularyDocument(source: "AudioWhisper").saving(draft), "AudioWhisper\nSwiftUI")
        }
    }

    func testReplacementCanWriteAHashtagButCannotBecomeAComment() throws {
        var draft = RebuildVocabularyDocument.Draft()
        draft.replacement = true
        draft.heard = "hash tag"
        draft.written = "#hashtag"
        let updated = try RebuildVocabularyDocument(source: "").saving(draft)
        XCTAssertEqual(CustomVocabulary(parsing: updated).apply(to: "Use hash tag"), "Use #hashtag")
        draft.heard = "# ignored"
        XCTAssertThrowsError(try RebuildVocabularyDocument(source: "").saving(draft))
    }

    func testSearchAndEditingPreserveCommentsAndUnrelatedRules() throws {
        let source = "# My names\nKubernetes\npost gress -> Postgres\nuh -> \n\n# Keep this note\n"
        let document = RebuildVocabularyDocument(source: source)
        XCTAssertEqual(document.entries.count, 3)
        let match = try XCTUnwrap(document.matching("POSTGRES").first)
        XCTAssertEqual(match.heard, "post gress")
        var draft = RebuildVocabularyDocument.Draft(entry: match)
        draft.written = "PostgreSQL"
        let updated = try document.saving(draft)
        XCTAssertEqual(updated, source.replacingOccurrences(of: "-> Postgres", with: "-> PostgreSQL"))
        let removed = try RebuildVocabularyDocument(source: updated).removing(document.entries[0])
        XCTAssertTrue(removed.contains("# Keep this note"))
        XCTAssertFalse(CustomVocabulary(parsing: removed).terms.contains("Kubernetes"))
        XCTAssertEqual(CustomVocabulary(parsing: removed).replacements.last?.written, "")
    }

    func testAddValidatesDuplicatesDelimitersAndStaleEdits() throws {
        let document = RebuildVocabularyDocument(source: "AudioWhisper\npost gress -> Postgres")
        var draft = RebuildVocabularyDocument.Draft()
        draft.written = "audiowhisper"
        XCTAssertThrowsError(try document.saving(draft))
        for invalid in ["One\nTwo", "one -> two", "# ignored"] {
            draft.written = invalid
            XCTAssertThrowsError(try document.saving(draft))
        }
        draft.written = "SwiftUI"
        XCTAssertEqual(CustomVocabulary(parsing: try document.saving(draft)).terms, ["AudioWhisper", "SwiftUI"])
        let stale = RebuildVocabularyDocument(source: "Another name\npost gress -> Postgres")
        XCTAssertThrowsError(try stale.saving(.init(entry: document.entries[0])))
        XCTAssertThrowsError(try stale.removing(document.entries[0]))
    }

    func testCorrectionSuggestsOnlyTheChangedPhraseAndKeepsSentencePunctuationOut() {
        let draft = RebuildVocabularyDocument.correction(from: "I use post gress.", to: "I use Postgres.")
        XCTAssertTrue(draft.replacement)
        XCTAssertEqual(draft.heard, "post gress")
        XCTAssertEqual(draft.written, "Postgres")
        let technical = RebuildVocabularyDocument.correction(from: "I use c#", to: "I use C#")
        XCTAssertEqual(technical.heard, "c#")
        XCTAssertEqual(technical.written, "C#")
        let unchanged = RebuildVocabularyDocument.correction(from: "Same text", to: "Same text")
        XCTAssertTrue(unchanged.heard.isEmpty)
        let long = RebuildVocabularyDocument.correction(from: Array(repeating: "old", count: 30).joined(separator: " "),
                                                       to: "A completely different transcript")
        XCTAssertTrue(long.heard.isEmpty, "Never prefill an entire long transcript as a replacement")
    }
}
