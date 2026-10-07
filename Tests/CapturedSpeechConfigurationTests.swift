import XCTest
@testable import AudioWhisper

private final class CapturedParakeet: ParakeetTranscribing {
    var selectedModel: ParakeetModel?
    func transcribe(audioFileURL: URL, pythonPath: String?) async throws -> String { "raw speech" }
    func transcribe(audioFileURL: URL, pythonPath: String?, model: ParakeetModel) async throws -> String {
        selectedModel = model
        return "raw speech"
    }
}

@MainActor
final class CapturedSpeechConfigurationTests: IsolatedXCTestCase {
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
}
