import XCTest
@testable import AudioWhisper

final class WritingSettingsTests: IsolatedXCTestCase {
    private let keys: [AppDefaults.Key] = [
        .customVocabulary, .removeFillerWords, .spokenPunctuation, .matchCursorContext, .restoreClipboardAfterPaste
    ]

    override func setUp() {
        super.setUp()
        keys.forEach(AppDefaults.removeValue(for:))
    }

    override func tearDown() {
        keys.forEach(AppDefaults.removeValue(for:))
        super.tearDown()
    }

    func testDefaultsFavourSafeRulesOnly() {
        XCTAssertEqual(AppDefaults.customVocabulary, "")
        XCTAssertTrue(AppDefaults.removeFillerWords)
        XCTAssertFalse(AppDefaults.spokenPunctuation, "someone who has not asked for it may mean the word")
        XCTAssertTrue(AppDefaults.matchCursorContext)
        XCTAssertFalse(AppDefaults.restoreClipboardAfterPaste, "the transcript stays on the clipboard unless asked")
    }

    @MainActor
    func testTheClipboardIsOnlyLentWhenTheUserAsked() {
        let services = RebuildSessionServices.testDefaults
        XCTAssertTrue(services.clipboardKeeper() == nil)
        AppDefaults.restoreClipboardAfterPaste = true
        XCTAssertTrue(services.clipboardKeeper() != nil)
    }

    func testSessionOptionsReflectTheStoredSettings() {
        AppDefaults.customVocabulary = "Kubernetes\npost gress -> Postgres"
        AppDefaults.removeFillerWords = false
        AppDefaults.spokenPunctuation = true
        let options = TranscriptFormattingOptions.current
        XCTAssertEqual(options.vocabulary.terms, ["Kubernetes"])
        XCTAssertEqual(options.vocabulary.replacements.count, 1)
        XCTAssertFalse(options.removeFillers)
        XCTAssertTrue(options.spokenPunctuation)
    }

    func testVocabularySummary() {
        XCTAssertEqual(RebuildWritingRulesCard.summary(of: .empty), "No vocabulary yet.")
        XCTAssertEqual(RebuildWritingRulesCard.summary(of: CustomVocabulary(parsing: "A\nB\nx -> y")), "2 words, 1 rewrite")
        XCTAssertEqual(RebuildWritingRulesCard.summary(of: CustomVocabulary(parsing: "x -> y\nz -> w")), "2 rewrites")
    }
}

private extension RebuildSessionServices {
    static var testDefaults: Self {
        Self(
            start: { _ in false }, stop: { nil }, cancel: {}, transcribe: { _, _, _ in throw CancellationError() },
            copy: { _ in }, save: { _, _, _ in }, interruptionSource: nil)
    }
}
