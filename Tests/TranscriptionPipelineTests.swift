import XCTest
@testable import AudioWhisper

/// Test-only stub that lets `TranscriptionPipeline` exercise a real success
/// path without hitting WhisperKit / Parakeet. `SpeechToTextService` is a
/// non-final class and `TranscriptionPipeline` injects it via its initializer,
/// so overriding `transcribeRaw(...)` is a legitimate seam.
private final class StubSpeechToTextService: SpeechToTextService, @unchecked Sendable {
    /// Result returned by `transcribeRaw`. Defaults to a fixed transcript.
    var rawResult: Result<String, Error> = .success("hello world")
    private(set) var transcribeRawCallCount = 0
    private(set) var lastAudioURL: URL?
    private(set) var lastProvider: TranscriptionProvider?
    private(set) var lastModel: WhisperModel?

    override func transcribeRaw(
        audioURL: URL,
        provider: TranscriptionProvider,
        model: WhisperModel? = nil
    ) async throws -> String {
        transcribeRawCallCount += 1
        lastAudioURL = audioURL
        lastProvider = provider
        lastModel = model
        return try rawResult.get()
    }
}

final class TranscriptionPipelineTests: XCTestCase {

    // MARK: - Configuration Tests

    func testTranscriptionPipelineConfigDefaults() {
        let config = TranscriptionPipelineConfig(provider: .parakeet)

        XCTAssertEqual(config.provider, .parakeet)
        XCTAssertNil(config.whisperModel)
        XCTAssertTrue(config.applySemanticCorrection)
        XCTAssertNil(config.sourceAppBundleId)
    }

    func testTranscriptionPipelineConfigWithAllParameters() {
        let config = TranscriptionPipelineConfig(
            provider: .local,
            whisperModel: .base,
            applySemanticCorrection: false,
            sourceAppBundleId: "com.apple.Notes"
        )

        XCTAssertEqual(config.provider, .local)
        XCTAssertEqual(config.whisperModel, .base)
        XCTAssertFalse(config.applySemanticCorrection)
        XCTAssertEqual(config.sourceAppBundleId, "com.apple.Notes")
    }

    func testTranscriptionPipelineConfigLocalProviderRequiresModel() {
        let config = TranscriptionPipelineConfig(provider: .local, whisperModel: .tiny)
        XCTAssertNotNil(config.whisperModel)
    }

    func testTranscriptionPipelineConfigParakeetProviderNoModelNeeded() {
        let config = TranscriptionPipelineConfig(provider: .parakeet)
        XCTAssertNil(config.whisperModel)
    }

    // MARK: - Pipeline Step Tests

    func testPipelineStepRawValues() {
        XCTAssertEqual(TranscriptionPipeline.PipelineStep.validating.rawValue, "Validating audio...")
        XCTAssertEqual(TranscriptionPipeline.PipelineStep.transcribing.rawValue, "Transcribing...")
        XCTAssertEqual(TranscriptionPipeline.PipelineStep.correcting.rawValue, "Applying corrections...")
        XCTAssertEqual(TranscriptionPipeline.PipelineStep.complete.rawValue, "Complete")
    }

    func testPipelineStepAllCases() {
        let allCases: [TranscriptionPipeline.PipelineStep] = [
            .validating, .transcribing, .correcting, .complete
        ]
        XCTAssertEqual(allCases.count, 4)
    }

    // MARK: - Progress Notification Tests

    @MainActor
    func testPostProgressSendsNotification() async {
        let pipeline = TranscriptionPipeline()
        let expectation = expectation(forNotification: .transcriptionProgress, object: nil) { notification in
            let step = notification.object as? String
            return step == TranscriptionPipeline.PipelineStep.validating.rawValue
        }

        pipeline.postProgress(.validating)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    @MainActor
    func testPostProgressSendsCorrectStepValue() async {
        let pipeline = TranscriptionPipeline()
        var receivedStep: String?
        let expectation = expectation(forNotification: .transcriptionProgress, object: nil) { notification in
            receivedStep = notification.object as? String
            return true
        }

        pipeline.postProgress(.transcribing)

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(receivedStep, "Transcribing...")
    }

    // MARK: - Happy Path Tests (real success path via injected stub)

    /// Drives a full successful `transcribe(...)` with semantic correction
    /// disabled and asserts the pipeline returns the stub provider's raw
    /// transcript with a `nil` correction outcome.
    @MainActor
    func testTranscribeSuccessReturnsRawTextWhenCorrectionDisabled() async throws {
        let stub = StubSpeechToTextService()
        stub.rawResult = .success("the quick brown fox")
        let pipeline = TranscriptionPipeline(speechService: stub)
        let tempURL = createTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let config = TranscriptionPipelineConfig(
            provider: .parakeet,
            applySemanticCorrection: false
        )

        let result = try await pipeline.transcribe(audioURL: tempURL, config: config)

        XCTAssertEqual(result.text, "the quick brown fox")
        XCTAssertNil(result.correctionOutcome,
                     "Correction outcome must be nil when correction is disabled")
        XCTAssertEqual(stub.transcribeRawCallCount, 1)
        XCTAssertEqual(stub.lastProvider, .parakeet)
        XCTAssertEqual(stub.lastAudioURL, tempURL)
    }

    /// Drives a full successful `transcribe(...)` with semantic correction
    /// enabled but `semanticCorrectionMode == .off` so the real
    /// `SemanticCorrectionService` deterministically returns `.skipped`.
    /// Asserts both the final transcript text and the correction outcome.
    @MainActor
    func testTranscribeSuccessReturnsSkippedOutcomeWhenModeOff() async throws {
        let previousMode = UserDefaults.standard.string(forKey: "semanticCorrectionMode")
        UserDefaults.standard.set(SemanticCorrectionMode.off.rawValue,
                                  forKey: "semanticCorrectionMode")
        defer {
            if let previousMode = previousMode {
                UserDefaults.standard.set(previousMode, forKey: "semanticCorrectionMode")
            } else {
                UserDefaults.standard.removeObject(forKey: "semanticCorrectionMode")
            }
        }

        let stub = StubSpeechToTextService()
        stub.rawResult = .success("transcribed text")
        let pipeline = TranscriptionPipeline(speechService: stub)
        let tempURL = createTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let config = TranscriptionPipelineConfig(
            provider: .parakeet,
            applySemanticCorrection: true
        )

        let result = try await pipeline.transcribe(audioURL: tempURL, config: config)

        XCTAssertEqual(result.text, "transcribed text")
        guard case .skipped(let skippedText)? = result.correctionOutcome else {
            return XCTFail("Expected .skipped outcome, got \(String(describing: result.correctionOutcome))")
        }
        XCTAssertEqual(skippedText, "transcribed text")
        XCTAssertEqual(stub.transcribeRawCallCount, 1)
    }

    /// `transcribeRaw(...)` convenience wrapper returns the provider transcript
    /// unchanged and never attempts correction.
    @MainActor
    func testTranscribeRawSuccessReturnsProviderText() async throws {
        let stub = StubSpeechToTextService()
        stub.rawResult = .success("raw provider output")
        let pipeline = TranscriptionPipeline(speechService: stub)
        let tempURL = createTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let text = try await pipeline.transcribeRaw(audioURL: tempURL, provider: .parakeet)

        XCTAssertEqual(text, "raw provider output")
        XCTAssertEqual(stub.transcribeRawCallCount, 1)
        XCTAssertEqual(stub.lastProvider, .parakeet)
    }

    /// A provider failure must propagate out of the pipeline rather than being
    /// silently swallowed.
    @MainActor
    func testTranscribePropagatesProviderError() async {
        let stub = StubSpeechToTextService()
        stub.rawResult = .failure(SpeechToTextError.transcriptionFailed("boom"))
        let pipeline = TranscriptionPipeline(speechService: stub)
        let tempURL = createTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let config = TranscriptionPipelineConfig(provider: .parakeet)

        do {
            _ = try await pipeline.transcribe(audioURL: tempURL, config: config)
            XCTFail("Expected provider error to propagate")
        } catch let error as SpeechToTextError {
            guard case .transcriptionFailed(let message) = error else {
                return XCTFail("Expected .transcriptionFailed, got \(error)")
            }
            XCTAssertEqual(message, "boom")
        } catch {
            XCTFail("Expected SpeechToTextError, got \(error)")
        }
    }

    // MARK: - Audio Validation Integration Tests

    @MainActor
    func testTranscribeFailsForNonExistentFile() async {
        let pipeline = TranscriptionPipeline()
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/audio.m4a")
        let config = TranscriptionPipelineConfig(provider: .parakeet)

        do {
            _ = try await pipeline.transcribe(audioURL: nonExistentURL, config: config)
            XCTFail("Expected transcription to fail for non-existent file")
        } catch {
            XCTAssertTrue(error is SpeechToTextError)
        }
    }

    @MainActor
    func testTranscribeRawFailsForNonExistentFile() async {
        let pipeline = TranscriptionPipeline()
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/audio.m4a")

        do {
            _ = try await pipeline.transcribeRaw(audioURL: nonExistentURL, provider: .parakeet)
            XCTFail("Expected transcription to fail for non-existent file")
        } catch {
            XCTAssertTrue(error is SpeechToTextError)
        }
    }

    /// `.local` with no `WhisperModel` must fail with the model-required error.
    /// Using the real `SpeechToTextService` so the model guard is exercised.
    @MainActor
    func testTranscribeRawLocalWithoutModelThrowsModelRequiredError() async {
        let pipeline = TranscriptionPipeline()
        let tempURL = createTemporaryAudioFile()
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            _ = try await pipeline.transcribeRaw(audioURL: tempURL, provider: .local, model: nil)
            XCTFail("Expected failure when no model provided for local provider")
        } catch let error as SpeechToTextError {
            guard case .transcriptionFailed(let message) = error else {
                return XCTFail("Expected .transcriptionFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("model required"),
                          "Error should mention model requirement, got: \(message)")
        } catch {
            XCTFail("Expected SpeechToTextError, got \(error)")
        }
    }

    // MARK: - Config Builder Pattern Tests

    func testConfigWithSemanticCorrectionDisabled() {
        let config = TranscriptionPipelineConfig(
            provider: .parakeet,
            applySemanticCorrection: false
        )
        XCTAssertFalse(config.applySemanticCorrection)
    }

    func testConfigWithSourceAppBundleId() {
        let config = TranscriptionPipelineConfig(
            provider: .local,
            whisperModel: .small,
            sourceAppBundleId: "com.example.testapp"
        )
        XCTAssertEqual(config.sourceAppBundleId, "com.example.testapp")
    }

    // MARK: - Provider Tests

    func testConfigSupportsAllProviders() {
        for provider in TranscriptionProvider.allCases {
            let config: TranscriptionPipelineConfig
            if provider == .local {
                config = TranscriptionPipelineConfig(provider: provider, whisperModel: .base)
            } else {
                config = TranscriptionPipelineConfig(provider: provider)
            }
            XCTAssertEqual(config.provider, provider)
        }
    }

    func testConfigSupportsAllWhisperModels() {
        for model in WhisperModel.allCases {
            let config = TranscriptionPipelineConfig(
                provider: .local,
                whisperModel: model
            )
            XCTAssertEqual(config.whisperModel, model)
        }
    }

    // MARK: - Helpers

    private func createTemporaryAudioFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("test_audio_\(UUID().uuidString).m4a")
        // Create a minimal valid file for testing
        FileManager.default.createFile(atPath: fileURL.path, contents: Data([0x00, 0x00, 0x00, 0x20]), attributes: nil)
        return fileURL
    }
}
