import XCTest
@testable import AudioWhisper

final class LocalWhisperPromptTests: XCTestCase {
    func testPromptTokensLeadWithASpaceAndDropSpecialTokens() {
        var encoded: String?
        let tokens = LocalWhisperService.promptTokens(
            for: "  Kubernetes, AudioWhisper \n", encode: { encoded = $0; return [10, 50_300, 20] },
            specialTokenBegin: 50_257)
        XCTAssertEqual(encoded, " Kubernetes, AudioWhisper")
        XCTAssertEqual(tokens, [10, 20])
    }

    func testBlankOrAllSpecialPromptIsNoPrompt() {
        XCTAssertNil(LocalWhisperService.promptTokens(for: "  ", encode: { _ in [1] }, specialTokenBegin: 50_257))
        XCTAssertNil(LocalWhisperService.promptTokens(for: "x", encode: { _ in [50_258] }, specialTokenBegin: 50_257))
    }

    func testDecodingOptionsTranscribeWithAutoLanguageAndNoPromptWithoutATokenizer() {
        let options = LocalWhisperService.decodingOptions(prompt: "Kubernetes", tokenizer: nil)
        XCTAssertEqual(options.task, .transcribe)
        XCTAssertNil(options.language)
        XCTAssertNil(options.promptTokens)
    }

    func testPromptEchoIsRecognisedButRealSpeechIsNot() {
        let prompt = "Kubernetes, AudioWhisper"
        XCTAssertTrue(LocalWhisperService.isPromptEcho(" Kubernetes, AudioWhisper.", prompt: prompt))
        XCTAssertTrue(LocalWhisperService.isPromptEcho("kubernetes audiowhisper", prompt: prompt))
        XCTAssertFalse(LocalWhisperService.isPromptEcho("Deploy Kubernetes", prompt: prompt))
        XCTAssertFalse(LocalWhisperService.isPromptEcho("...", prompt: prompt))
    }
}
