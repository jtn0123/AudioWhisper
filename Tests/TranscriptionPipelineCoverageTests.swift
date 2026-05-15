import XCTest
@testable import AudioWhisper

/// Coverage tests for `TranscriptionPipeline` validation/correction branches
/// and `TranscriptionResult`.
@MainActor
final class TranscriptionPipelineCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): pipeline reads `semanticCorrectionMode` from AppDefaults.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    // MARK: - TranscriptionResult

    func testTranscriptionResultHoldsTextAndOutcome() {
        let result = TranscriptionResult(
            text: "final",
            correctionOutcome: .applied("final")
        )
        XCTAssertEqual(result.text, "final")
        XCTAssertNotNil(result.correctionOutcome)
        XCTAssertEqual(result.correctionOutcome?.text, "final")
    }

    func testTranscriptionResultNilOutcome() {
        let result = TranscriptionResult(text: "raw", correctionOutcome: nil)
        XCTAssertEqual(result.text, "raw")
        XCTAssertNil(result.correctionOutcome)
    }

    // MARK: - Validation failure surfaces as SpeechToTextError

    func testTranscribeInvalidAudioThrowsSpeechToTextError() async {
        let pipeline = TranscriptionPipeline()
        let badURL = URL(fileURLWithPath: "/no/such/file.m4a")
        let config = TranscriptionPipelineConfig(provider: .parakeet)
        do {
            _ = try await pipeline.transcribe(audioURL: badURL, config: config)
            XCTFail("Expected validation failure")
        } catch let error as SpeechToTextError {
            if case .transcriptionFailed = error {
                // expected
            } else {
                XCTFail("Expected transcriptionFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected SpeechToTextError, got \(error)")
        }
    }

    func testTranscribeLocalWithoutModelFailsValidationOrModelGuard() async {
        let pipeline = TranscriptionPipeline()
        let url = makeFakeAudioFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let config = TranscriptionPipelineConfig(
            provider: .local,
            whisperModel: nil,
            applySemanticCorrection: false
        )
        do {
            _ = try await pipeline.transcribe(audioURL: url, config: config)
            XCTFail("Expected failure for local provider without model")
        } catch {
            XCTAssertTrue(error is SpeechToTextError)
        }
    }

    func testTranscribeRawConvenienceFailsForInvalidAudio() async {
        let pipeline = TranscriptionPipeline()
        let badURL = URL(fileURLWithPath: "/no/such/raw.m4a")
        do {
            _ = try await pipeline.transcribeRaw(audioURL: badURL, provider: .parakeet)
            XCTFail("Expected failure")
        } catch {
            XCTAssertTrue(error is SpeechToTextError)
        }
    }

    // MARK: - Progress

    func testPostProgressForEachStep() async {
        let pipeline = TranscriptionPipeline()
        for step in [TranscriptionPipeline.PipelineStep.validating,
                     .transcribing, .correcting, .complete] {
            let expectation = expectation(forNotification: .transcriptionProgress, object: nil) {
                ($0.object as? String) == step.rawValue
            }
            pipeline.postProgress(step)
            await fulfillment(of: [expectation], timeout: 1.0)
        }
    }

    // MARK: - Helpers

    private func makeFakeAudioFile() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pipeline_cov_\(UUID().uuidString).m4a")
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data(repeating: 0, count: 64),
            attributes: nil
        )
        return url
    }
}
