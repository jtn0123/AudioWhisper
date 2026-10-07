import XCTest
@testable import AudioWhisper

private final class CapturedParakeet: ParakeetTranscribing {
    var selectedModel: ParakeetModel?
    var onTranscribe: (() throws -> Void)?
    func transcribe(audioFileURL: URL, pythonPath: String?) async throws -> String { "raw speech" }
    func transcribe(audioFileURL: URL, pythonPath: String?, model: ParakeetModel) async throws -> String {
        try onTranscribe?()
        selectedModel = model
        return "raw speech"
    }
}

private final class OrderedCorrection: MLDaemonManaging {
    var onCorrect: (() -> Void)?
    func correct(repo: String, text: String, prompt: String?) async throws -> String {
        onCorrect?()
        return "Raw speech."
    }
    func ping() async -> Bool { true }
}

@MainActor
final class CapturedSpeechConfigurationTests: IsolatedXCTestCase {
    override func tearDown() async throws {
        await MLDaemonManager.shared.setTestResponder(nil)
        try await super.tearDown()
    }
    func testExplicitPipelineModelWinsOverDefaultsAndTaskLocalSettings() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        AppDefaults.selectedParakeetModel = .v2English
        let parakeet = CapturedParakeet()
        let speech = SpeechToTextService(
            parakeetService: parakeet, preparePython: { URL(fileURLWithPath: "/fixture/python") })
        let pipeline = TranscriptionPipeline(speechService: speech)
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        let selected = TranscriptionPipelineConfig(
            provider: .parakeet, applySemanticCorrection: false, parakeetModel: .v3Multilingual, correctionMode: .off)
        let stale = TranscriptionPipelineConfig(
            provider: .parakeet, applySemanticCorrection: false, parakeetModel: .v2English, correctionMode: .off)
        let result = try await TranscriptionProgress.$pipelineConfig.withValue(stale) {
            try await pipeline.transcribe(audioURL: audio, config: selected)
        }
        XCTAssertEqual(result.text, "raw speech")
        XCTAssertEqual(parakeet.selectedModel, .v3Multilingual)
    }

    func testRecognitionFinishesBeforeWritingAndFailureSkipsWriting() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        await MLDaemonManager.shared.setTestResponder { method, _ in
            XCTFail("Raw speech must not send an editor warmup request: \(method)")
            return ["success": true]
        }
        let parakeet = CapturedParakeet()
        let daemon = OrderedCorrection()
        var stages: [String] = []
        parakeet.onTranscribe = { stages.append("speech") }
        daemon.onCorrect = { stages.append("writing") }
        let fixturePython = { URL(fileURLWithPath: "/fixture/python") }
        let pipeline = TranscriptionPipeline(
            speechService: SpeechToTextService(parakeetService: parakeet, preparePython: fixturePython),
            correctionService: SemanticCorrectionService(
                mlxService: MLXCorrectionService(daemon: daemon), preparePython: fixturePython))
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        let config = TranscriptionPipelineConfig(
            provider: .parakeet, applySemanticCorrection: true, parakeetModel: .v2English,
            correctionMode: .localMLX, correctionModelRepo: "fixture/model")
        let result = try await pipeline.transcribe(audioURL: audio, config: config)
        XCTAssertEqual(stages, ["speech", "writing"])
        XCTAssertEqual(result.originalText, "raw speech")
        stages.removeAll()
        parakeet.onTranscribe = { stages.append("speech"); throw ParakeetError.modelNotReady }
        do {
            _ = try await pipeline.transcribe(audioURL: audio, config: config)
            XCTFail("Recognition failure must abort before writing")
        } catch let error as ParakeetError { XCTAssertEqual(error, .modelNotReady) }
        XCTAssertEqual(stages, ["speech"])
    }

}
