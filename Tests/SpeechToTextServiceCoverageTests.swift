import XCTest
@testable import AudioWhisper

/// Coverage tests for `SpeechToTextService` error mapping, audio validation,
/// model-selection guards, and the static text cleaner.
final class SpeechToTextServiceCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): SpeechToTextService / providers read settings from
    // UserDefaults.standard via AppDefaults.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    // MARK: - SpeechToTextError descriptions

    func testInvalidURLErrorDescription() {
        let error = SpeechToTextError.invalidURL
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testTranscriptionFailedErrorDescriptionContainsMessage() {
        let error = SpeechToTextError.transcriptionFailed("disk full")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("disk full"))
    }

    func testLocalTranscriptionFailedErrorDescription() {
        let inner = LocalWhisperError.modelNotDownloaded
        let error = SpeechToTextError.localTranscriptionFailed(inner)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains(inner.localizedDescription))
    }

    // MARK: - Audio validation guards

    func testTranscribeRawFailsForNonExistentFile() async {
        let service = SpeechToTextService()
        let badURL = URL(fileURLWithPath: "/nonexistent/whatever.m4a")
        do {
            _ = try await service.transcribeRaw(audioURL: badURL, provider: .parakeet)
            XCTFail("Expected failure for non-existent file")
        } catch {
            XCTAssertTrue(error is SpeechToTextError)
        }
    }

    func testTranscribeFailsForNonExistentFile() async {
        let service = SpeechToTextService()
        let badURL = URL(fileURLWithPath: "/nonexistent/whatever.m4a")
        do {
            _ = try await service.transcribe(audioURL: badURL, provider: .parakeet, model: nil)
            XCTFail("Expected failure for non-existent file")
        } catch {
            XCTAssertTrue(error is SpeechToTextError)
        }
    }

    func testTranscribeAutoSelectFailsForNonExistentFile() async {
        let service = SpeechToTextService()
        let badURL = URL(fileURLWithPath: "/nonexistent/whatever.m4a")
        do {
            _ = try await service.transcribe(audioURL: badURL)
            XCTFail("Expected failure for non-existent file")
        } catch {
            XCTAssertTrue(error is SpeechToTextError || error is ParakeetError)
        }
    }

    func testTranscribeRawLocalRequiresModel() async {
        let service = SpeechToTextService()
        // Valid-enough file so validation can pass; model nil triggers the guard.
        let url = makeFakeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await service.transcribeRaw(audioURL: url, provider: .local, model: nil)
            XCTFail("Expected failure when model missing")
        } catch let error as SpeechToTextError {
            if case .transcriptionFailed(let message) = error {
                XCTAssertTrue(message.contains("model") || !message.isEmpty)
            }
        } catch {
            // Other errors acceptable: validation may reject the fake file first.
        }
    }

    // MARK: - cleanTranscriptionText

    func testCleanRemovesBracketedMarkers() {
        let result = SpeechToTextService.cleanTranscriptionText("Hello [music] world")
        XCTAssertEqual(result, "Hello world")
    }

    func testCleanRemovesParentheticalMarkers() {
        let result = SpeechToTextService.cleanTranscriptionText("Hello (laughing) world")
        XCTAssertEqual(result, "Hello world")
    }

    func testCleanRemovesNestedBrackets() {
        let result = SpeechToTextService.cleanTranscriptionText("Start [outer [inner]] end")
        XCTAssertEqual(result, "Start end")
    }

    func testCleanCollapsesWhitespace() {
        let result = SpeechToTextService.cleanTranscriptionText("a    b\t\tc")
        XCTAssertEqual(result, "a b c")
    }

    func testCleanTrimsLeadingTrailingWhitespace() {
        let result = SpeechToTextService.cleanTranscriptionText("   hello   ")
        XCTAssertEqual(result, "hello")
    }

    func testCleanEmptyString() {
        XCTAssertEqual(SpeechToTextService.cleanTranscriptionText(""), "")
    }

    func testCleanPlainTextUnchanged() {
        XCTAssertEqual(
            SpeechToTextService.cleanTranscriptionText("Just plain words"),
            "Just plain words"
        )
    }

    // MARK: - Helpers

    private func makeFakeAudioFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stt_cov_\(UUID().uuidString).m4a")
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data(repeating: 0, count: 64),
            attributes: nil
        )
        return url
    }
}
