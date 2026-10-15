import XCTest
@testable import AudioWhisper

final class TranscriptFormatterTests: XCTestCase {
    // MARK: Identity

    func testDefaultOptionsLeaveTextUntouched() {
        let text = "Um, so  e.g. this , stays exactly. period"
        XCTAssertEqual(TranscriptFormatter.format(text, options: .none), text)
    }

    // MARK: Fillers

    func testSentenceOpeningFillerHandsItsCapitalOn() {
        XCTAssertEqual(TranscriptFormatter.removeFillers("Um, so I think it works."), "So I think it works.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("It works. Uh, maybe not."), "It works. Maybe not.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("Uh I agree."), "I agree.")
    }

    func testMidSentenceFillersAreRemovedWithTheirCommas() {
        XCTAssertEqual(TranscriptFormatter.removeFillers("I was, uh, thinking about it."), "I was thinking about it.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("I was uhm thinking."), "I was thinking.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("So, um, I left."), "So I left.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("Deploy it, uh now."), "Deploy it, now.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("I said uh, never mind."), "I said never mind.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("I agree, um."), "I agree.")
    }

    func testUmIsKeptWhereItIsAWord() {
        XCTAssertEqual(TranscriptFormatter.removeFillers("Wir treffen uns um 5 Uhr."), "Wir treffen uns um 5 Uhr.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("Um carro azul."), "Um carro azul.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("Ich gehe, um zu essen."), "Ich gehe, um zu essen.")
    }

    func testMeaningfulLookalikesSurvive() {
        XCTAssertEqual(TranscriptFormatter.removeFillers("Uh-oh, that broke."), "Uh-oh, that broke.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("The umbrella is here."), "The umbrella is here.")
        XCTAssertEqual(TranscriptFormatter.removeFillers("Use e.g. this one."), "Use e.g. this one.")
    }

    func testFillersOnALineAfterABreakAreRemoved() {
        XCTAssertEqual(TranscriptFormatter.removeFillers("First.\nUm, second."), "First.\nSecond.")
    }

    // MARK: Spoken punctuation

    func testSpokenMarksBecomePunctuation() {
        XCTAssertEqual(
            TranscriptFormatter.applySpokenPunctuation("Hi comma how are you question mark"), "Hi, how are you?")
        XCTAssertEqual(TranscriptFormatter.applySpokenPunctuation("Wait exclamation point"), "Wait!")
        XCTAssertEqual(TranscriptFormatter.applySpokenPunctuation("Note colon buy milk"), "Note: buy milk")
    }

    func testWhisperPunctuationAroundTheCommandIsAbsorbed() {
        XCTAssertEqual(TranscriptFormatter.applySpokenPunctuation("Hello, comma, how are you?"), "Hello, how are you?")
        XCTAssertEqual(TranscriptFormatter.applySpokenPunctuation("I'm done. Period."), "I'm done.")
    }

    func testLineBreaksAndCapitalisation() {
        XCTAssertEqual(
            TranscriptFormatter.applySpokenPunctuation("first line new line second line"), "first line\nSecond line")
        XCTAssertEqual(
            TranscriptFormatter.applySpokenPunctuation("Dear Sam, new paragraph. thanks for writing"),
            "Dear Sam\n\nThanks for writing")
    }

    func testPeriodAsANounIsKept() {
        let text = "Over a period of three weeks the period ended"
        XCTAssertEqual(TranscriptFormatter.applySpokenPunctuation(text), text)
        XCTAssertEqual(TranscriptFormatter.applySpokenPunctuation("It is done period Next one"), "It is done. Next one")
    }

    func testOptionsComposeInOrder() {
        let options = TranscriptFormattingOptions(
            vocabulary: CustomVocabulary(parsing: "Kubernetes"), removeFillers: true, spokenPunctuation: true)
        XCTAssertEqual(
            TranscriptFormatter.format("Um, deploy kubernetes comma uh now period", options: options),
            "Deploy Kubernetes, now.")
    }
}

final class CustomVocabularyTests: XCTestCase {
    func testParsingSeparatesTermsReplacementsAndComments() {
        let vocabulary = CustomVocabulary(parsing: """
            # my words
            Kubernetes
              post gress -> Postgres
            jay son => JSON

            Kubernetes
             -> nothing
            """)
        XCTAssertEqual(vocabulary.terms, ["Kubernetes"])
        XCTAssertEqual(vocabulary.replacements, [
            .init(heard: "post gress", written: "Postgres"), .init(heard: "jay son", written: "JSON")
        ])
    }

    func testTermsFixCaseOnWholeWordsOnly() {
        let vocabulary = CustomVocabulary(terms: ["GitHub", "AI"])
        XCTAssertEqual(vocabulary.apply(to: "push to github and ask the ai"), "push to GitHub and ask the AI")
        XCTAssertEqual(vocabulary.apply(to: "said aim and plain"), "said aim and plain")
    }

    func testCamelCaseTermsMatchTheirSpokenSplit() {
        let vocabulary = CustomVocabulary(terms: ["AudioWhisper", "PostgreSQL"])
        XCTAssertEqual(vocabulary.apply(to: "open audio whisper"), "open AudioWhisper")
        XCTAssertEqual(vocabulary.apply(to: "audio-whisper on postgre sql"), "AudioWhisper on PostgreSQL")
    }

    func testReplacementsAreLiteralAndCaseInsensitive() {
        let vocabulary = CustomVocabulary(replacements: [.init(heard: "dollar sign", written: "$1 (\\n)")])
        XCTAssertEqual(vocabulary.apply(to: "Dollar  sign here"), "$1 (\\n) here")
    }

    func testMultiWordTermsTolerateSpacing() {
        let vocabulary = CustomVocabulary(terms: ["Visual Studio Code"])
        XCTAssertEqual(vocabulary.apply(to: "open visual  studio code now"), "open Visual Studio Code now")
    }

    func testPromptListsSpellingsWithinTheBudget() {
        let vocabulary = CustomVocabulary(terms: ["Kubernetes", "AudioWhisper"], replacements: [
            .init(heard: "post gress", written: "Postgres"), .init(heard: "skip", written: "")
        ])
        XCTAssertEqual(vocabulary.promptText, "Kubernetes, AudioWhisper, Postgres")
        XCTAssertNil(CustomVocabulary.empty.promptText)

        let long = CustomVocabulary(terms: (0..<200).map { "Term\($0)" })
        XCTAssertLessThanOrEqual(long.promptText?.count ?? 0, CustomVocabulary.maxPromptCharacters)
        XCTAssertTrue(long.promptText?.hasPrefix("Term0, Term1") == true)
    }

    func testCamelCaseSplitting() {
        XCTAssertEqual(CustomVocabulary.camelCaseParts(of: "iPhone"), ["i", "Phone"])
        XCTAssertEqual(CustomVocabulary.camelCaseParts(of: "NASA"), ["NASA"])
        XCTAssertEqual(CustomVocabulary.camelCaseParts(of: "ChatGPT"), ["Chat", "GPT"])
    }
}

final class CursorContextFormatterTests: XCTestCase {
    func testStartOfFieldCapitalisesWithoutASpace() {
        XCTAssertEqual(CursorContextFormatter.fit("hello there", after: ""), "Hello there")
        XCTAssertEqual(CursorContextFormatter.fit("iPhone works", after: ""), "iPhone works")
    }

    func testAfterASentenceEndAddsASpaceAndKeepsTheCapital() {
        XCTAssertEqual(CursorContextFormatter.fit("We should go", after: "It is late."), " We should go")
        XCTAssertEqual(CursorContextFormatter.fit("we should go", after: "He said \"stop.\""), " We should go")
        XCTAssertEqual(CursorContextFormatter.fit("We should go", after: "It is late. "), "We should go")
    }

    func testMidSentenceLowercasesOnlyFunctionWords() {
        XCTAssertEqual(CursorContextFormatter.fit("We should go", after: "I told her that"), " we should go")
        XCTAssertEqual(CursorContextFormatter.fit("It’s fine", after: "and"), " it’s fine")
        XCTAssertEqual(CursorContextFormatter.fit("Paris is nice", after: "I think"), " Paris is nice")
        XCTAssertEqual(CursorContextFormatter.fit("I agree", after: "and"), " I agree")
        XCTAssertEqual(CursorContextFormatter.fit("NASA launched", after: "then"), " NASA launched")
    }

    func testNewLineAndOpenersNeedNoSpace() {
        XCTAssertEqual(CursorContextFormatter.fit("and then", after: "Done\n"), "And then")
        XCTAssertEqual(CursorContextFormatter.fit("The note", after: "see ("), "The note")
        XCTAssertEqual(CursorContextFormatter.fit("hello", after: "say \""), "hello", "an opening quote takes no space")
    }

    func testPunctuationAttachesToThePreviousWord() {
        XCTAssertEqual(CursorContextFormatter.fit(", and more", after: "apples"), ", and more")
    }

    func testUnknownContextOrLeadingSpaceIsLeftAlone() {
        XCTAssertEqual(CursorContextFormatter.fit("We go", after: nil), "We go")
        XCTAssertEqual(CursorContextFormatter.fit(" We go", after: "word"), " We go")
        XCTAssertEqual(CursorContextFormatter.fit("", after: "word"), "")
    }
}
