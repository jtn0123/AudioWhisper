import XCTest
import WhisperKit
@testable import AudioWhisper

@MainActor
final class LocalEngineFixtureTests: XCTestCase {
    private func requireRealEngines() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_E2E"] == "1", "Set RUN_E2E=1 for real local inference")
        try XCTSkipUnless(Arch.isAppleSilicon)
    }

    func testWhisperTranscribesSpeechAndReusesWarmModel() async throws {
        try requireRealEngines()
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"
        ))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        let peak = samples.map { abs($0) }.max() ?? 0
        print("REAL_WHISPER_AUDIO samples=\(samples.count) peak=\(peak)")
        XCTAssertGreaterThan(samples.count, 16_000, "The real speech fixture must contain decoded audio")
        XCTAssertGreaterThan(peak, 0.01, "The real speech fixture must not decode as silence")
        try await ModelManager.shared.downloadModel(.base)
        let service = LocalWhisperService.shared
        for run in 0..<2 {
            let start = ContinuousClock.now
            let text = try await service.transcribe(audioFileURL: audio, model: .base)
            let words = text.lowercased()
            XCTAssertTrue(["quick", "brown", "fox", "lazy", "dog"].filter(words.contains).count >= 4, text)
            print("REAL_WHISPER run=\(run) elapsed=\(start.duration(to: .now)) transcript=\(text)")
            if run == 0 && !words.contains("fox") {
                try await diagnoseCPUOnlyWhisper(audio: audio)
            }
        }
        try await service.verifyModel(.base)
        print("REAL_WHISPER verification=loaded")
    }

    private func diagnoseCPUOnlyWhisper(audio: URL) async throws {
        let path = try XCTUnwrap(WhisperKitStorage.localModelPath(for: .base))
        let config = WhisperKitConfig(
            modelFolder: path,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuOnly, audioEncoderCompute: .cpuOnly, textDecoderCompute: .cpuOnly
            ),
            verbose: true, logLevel: .debug
        )
        let reference = try await WhisperKit(config)
        let results = try await reference.transcribe(audioPath: audio.path)
        for result in results {
            print("REAL_WHISPER_CPU_ONLY language=\(result.language) text=\(result.text)")
            print("REAL_WHISPER_CPU_ONLY tokens=\(result.segments.flatMap { $0.tokens })")
        }
    }

    func testMLXCorrectionPerformsActualInferenceAndWarmRuntimeReuse() async throws {
        try requireRealEngines()
        let repo = "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        await MLXModelManager.shared.downloadModel(repo)
        XCTAssertTrue(MLXModelManager.shared.isModelCachedOnDisk(repo: repo))
        let prepareStart = ContinuousClock.now
        let python = try await UvBootstrap.ensureVenv(forceRefresh: true)
        let refreshed = prepareStart.duration(to: .now)
        let warmStart = ContinuousClock.now
        let samePython = try await UvBootstrap.ensureVenv()
        print("REAL_RUNTIME refreshed=\(refreshed) warm=\(warmStart.duration(to: .now))")
        XCTAssertEqual(python, samePython)
        let service = MLXCorrectionService()
        let original = "Their going to the store tomorow."
        let correctionStart = ContinuousClock.now
        let corrected = try await service.correct(
            text: original, modelRepo: repo, pythonPath: python.path,
            systemPrompt: "Correct spelling and grammar. Return only the corrected sentence, without explanation."
        )
        print("REAL_CORRECTION elapsed=\(correctionStart.duration(to: .now)) output=\(corrected)")
        XCTAssertNotEqual(corrected, original, "an unchanged fallback must not pass the real correction check")
        XCTAssertTrue(corrected.lowercased().contains("tomorrow"), corrected)
        XCTAssertTrue(corrected.lowercased().contains("store"), corrected)
    }
}
