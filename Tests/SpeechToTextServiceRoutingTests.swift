import XCTest
@testable import AudioWhisper

/// Fake WhisperKit provider. See `SpeechToTextServiceRoutingTests` for why this
/// is now possible.
private final class FakeLocalWhisper: LocalWhisperTranscribing, @unchecked Sendable {
    var result: Result<String, Error> = .success("local transcript")
    private(set) var callCount = 0
    private(set) var lastModel: WhisperModel?
    private(set) var lastURL: URL?

    func transcribe(
        audioFileURL: URL,
        model: WhisperModel,
        progressCallback: (@Sendable (String) -> Void)?
    ) async throws -> String {
        callCount += 1
        lastModel = model
        lastURL = audioFileURL
        progressCallback?("working")
        return try result.get()
    }
}

private final class FakeParakeet: ParakeetTranscribing {
    var result: Result<String, Error> = .success("parakeet transcript")
    private(set) var callCount = 0
    private(set) var lastURL: URL?

    func transcribe(audioFileURL: URL, pythonPath: String?) async throws -> String {
        callCount += 1
        lastURL = audioFileURL
        return try result.get()
    }
}

/// Routing, guards and output-cleaning inside `SpeechToTextService`.
///
/// Audit item A5. None of this was reachable before: the service hardcoded
/// `LocalWhisperService.shared` and `ParakeetService.shared` as `private let`s,
/// so any test would have needed a real downloaded model. `Services/` sat at
/// ~50% coverage largely because of that. The initializer now takes the two
/// providers, defaulting to the shared instances, so production behaviour is
/// unchanged and the routing is testable.
///
/// The Parakeet path is not exercised here: `transcribeWithParakeet` calls
/// `UvBootstrap.ensureVenv` before reaching the provider, which builds a real
/// Python environment. That remains covered by the nightly end-to-end job.
@MainActor
final class SpeechToTextServiceRoutingTests: XCTestCase {

    private var whisper: FakeLocalWhisper!
    private var parakeet: FakeParakeet!
    private var service: SpeechToTextService!
    private var tempFiles: [URL] = []

    override func setUp() async throws {
        try await super.setUp()
        whisper = FakeLocalWhisper()
        parakeet = FakeParakeet()
        service = SpeechToTextService(localWhisperService: whisper, parakeetService: parakeet)
    }

    override func tearDown() async throws {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
        try await super.tearDown()
    }

    /// A file that passes `AudioValidator`.
    private func makeAudioFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("routing_\(UUID().uuidString).m4a")
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data([0x00, 0x00, 0x00, 0x20]),
            attributes: nil
        )
        tempFiles.append(url)
        return url
    }

    // MARK: - Provider routing

    func testLocalProviderReachesWhisperWithTheRequestedModel() async throws {
        let url = makeAudioFile()
        whisper.result = .success("hello from whisper")

        let text = try await service.transcribeValidated(audioURL: url, provider: .local, model: .small)

        XCTAssertEqual(text, "hello from whisper")
        XCTAssertEqual(whisper.callCount, 1)
        XCTAssertEqual(whisper.lastModel, .small, "the requested model must be forwarded, not a default")
        XCTAssertEqual(whisper.lastURL, url)
        XCTAssertEqual(parakeet.callCount, 0, "the local provider must not touch Parakeet")
    }

    /// The guard that turns a missing model into a clear error instead of a
    /// crash or a silently-wrong default.
    func testLocalProviderWithoutAModelFailsWithoutCallingTheProvider() async {
        let url = makeAudioFile()

        do {
            _ = try await service.transcribeValidated(audioURL: url, provider: .local, model: nil)
            XCTFail("expected a transcriptionFailed error")
        } catch let error as SpeechToTextError {
            guard case .transcriptionFailed = error else {
                return XCTFail("expected .transcriptionFailed, got \(error)")
            }
        } catch {
            XCTFail("expected SpeechToTextError, got \(error)")
        }

        XCTAssertEqual(whisper.callCount, 0, "must not invoke the provider without a model")
    }

    // MARK: - Error mapping

    /// A domain error must survive rather than being flattened into a generic
    /// `.localTranscriptionFailed` — the UI branches on `.noSpeechDetected`.
    func testNoSpeechDetectedIsPreservedNotWrapped() async {
        let url = makeAudioFile()
        whisper.result = .failure(SpeechToTextError.noSpeechDetected)

        do {
            _ = try await service.transcribeValidated(audioURL: url, provider: .local, model: .base)
            XCTFail("expected an error")
        } catch let error as SpeechToTextError {
            guard case .noSpeechDetected = error else {
                return XCTFail("domain error was flattened into \(error)")
            }
        } catch {
            XCTFail("expected SpeechToTextError, got \(error)")
        }
    }

    /// A non-domain provider error is wrapped so callers can tell the two apart.
    func testArbitraryProviderErrorIsWrapped() async {
        let url = makeAudioFile()
        whisper.result = .failure(NSError(domain: "WhisperKit", code: 42))

        do {
            _ = try await service.transcribeValidated(audioURL: url, provider: .local, model: .base)
            XCTFail("expected an error")
        } catch let error as SpeechToTextError {
            guard case .localTranscriptionFailed = error else {
                return XCTFail("expected .localTranscriptionFailed, got \(error)")
            }
        } catch {
            XCTFail("expected SpeechToTextError, got \(error)")
        }
    }

    // MARK: - Output cleaning

    /// WhisperKit emits `[BLANK_AUDIO]` for silence. It is non-empty before
    /// cleaning, so it passes the provider's own emptiness check, then cleans
    /// down to "" — which would silently paste nothing.
    func testMarkerOnlyTranscriptBecomesNoSpeechDetected() async {
        let url = makeAudioFile()
        whisper.result = .success("[BLANK_AUDIO]")

        do {
            _ = try await service.transcribeValidated(audioURL: url, provider: .local, model: .base)
            XCTFail("a marker-only transcript must not be returned as text")
        } catch let error as SpeechToTextError {
            guard case .noSpeechDetected = error else {
                return XCTFail("expected .noSpeechDetected, got \(error)")
            }
        } catch {
            XCTFail("expected SpeechToTextError, got \(error)")
        }
    }

    func testBracketedMarkersAreStrippedFromRealTranscripts() async throws {
        let url = makeAudioFile()
        whisper.result = .success("[BLANK_AUDIO] the actual words (inaudible) here")

        let text = try await service.transcribeValidated(audioURL: url, provider: .local, model: .base)

        XCTAssertEqual(text, "the actual words here")
    }

    // MARK: - Validation

    /// `transcribeRaw` validates; `transcribeValidated` does not (audit item
    /// A4). A nonexistent file must therefore fail before the provider is hit.
    func testTranscribeRawRejectsAnInvalidFileBeforeCallingTheProvider() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does_not_exist_\(UUID().uuidString).m4a")

        do {
            _ = try await service.transcribeRaw(audioURL: missing, provider: .local, model: .base)
            XCTFail("expected validation to reject a missing file")
        } catch {
            // expected
        }

        XCTAssertEqual(whisper.callCount, 0, "validation must run before the provider")
    }
}
