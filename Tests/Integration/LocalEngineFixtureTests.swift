import XCTest
import CryptoKit
import CoreML
import WhisperKit
@testable import AudioWhisper

@MainActor
final class LocalEngineFixtureTests: XCTestCase {
    private func requireRealEngines() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_E2E"] == "1", "Set RUN_E2E=1 for real local inference")
        try XCTSkipUnless(Arch.isAppleSilicon)
    }

    func testWhisperCPUOnlyTranscribesSpeech() async throws {
        try requireRealEngines()
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        try await ModelManager.shared.downloadModel(.base)
        try await diagnoseCPUOnlyWhisper(audio: audio)
    }

    func testWhisperCompactMelInputTranscribesSpeech() async throws {
        try requireRealEngines()
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        try await ModelManager.shared.downloadModel(.base)
        let path = try XCTUnwrap(WhisperKitStorage.localModelPath(for: .base))
        let engine = try await WhisperKit(WhisperKitConfig(modelFolder: path, download: false))
        engine.audioEncoder = CompactMelEncoderDiagnostic(base: engine.audioEncoder)
        try await WhisperFixtureDiagnostics.describeFeatures(engine, audio: audio)
        let results = try await engine.transcribe(audioPath: audio.path)
        let text = results.map { $0.text }.joined(separator: " ")
        print("REAL_WHISPER_COMPACT transcript=\(text)")
        assertSpeechFixture(text)
    }

    func testWhisperDecoderWithReferenceEncoderFeatures() async throws {
        try requireRealEngines()
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        try await ModelManager.shared.downloadModel(.base)
        let path = try XCTUnwrap(WhisperKitStorage.localModelPath(for: .base))
        let engine = try await WhisperKit(WhisperKitConfig(
            modelFolder: path,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuOnly, audioEncoderCompute: .cpuOnly, textDecoderCompute: .cpuOnly),
            download: false))
        let referenceMel = try WhisperBoundaryReference.tensor("mel", shape: [1, 80, 1, 3000])
        let referenceEncoded = try WhisperBoundaryReference.tensor("encoded", shape: [1, 512, 1, 1500])
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        let padded = try XCTUnwrap(AudioProcessor.padOrTrimAudio(fromArray: samples))
        let melOutput = try await engine.featureExtractor.logMelSpectrogram(fromAudio: padded)
        let mel = try XCTUnwrap(melOutput as? MLMultiArray)
        let base = engine.audioEncoder
        let encodedOutput = try await base.encodeFeatures(mel)
        let actual = try XCTUnwrap(encodedOutput as? MLMultiArray)
        WhisperBoundaryReference.compare(mel, with: referenceMel, name: "mel")
        WhisperBoundaryReference.compare(actual, with: referenceEncoded, name: "encoded")
        if let model = (base as? AudioEncoder)?.model {
            try WhisperBoundaryReference.compareSynchronousEncoder(model, mel: referenceMel, reference: referenceEncoded)
        }
        engine.audioEncoder = ReferenceBoundaryEncoder(base: base, mel: referenceMel)
        let fromMel = try await engine.transcribe(audioPath: audio.path)
        print("REAL_WHISPER_REPLAY boundary=mel text=\(fromMel.map { $0.text }.joined(separator: " "))")
        engine.audioEncoder = ReferenceBoundaryEncoder(base: base, encoded: referenceEncoded)
        let fromEncoded = try await engine.transcribe(audioPath: audio.path)
        let text = fromEncoded.map { $0.text }.joined(separator: " ")
        print("REAL_WHISPER_REPLAY boundary=encoded text=\(text)")
        assertSpeechFixture(text)
    }

    func testWhisperTranscribesSpeechAndReusesWarmModel() async throws {
        try requireRealEngines()
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"
        ))
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        let peak = samples.map { abs($0) }.max() ?? 0
        let fingerprint = samples.withUnsafeBytes { SHA256.hash(data: Data($0)).map { String(format: "%02x", $0) }.joined() }
        print("REAL_WHISPER_AUDIO samples=\(samples.count) peak=\(peak) sha256=\(fingerprint)")
        print("REAL_WHISPER_ENV os=\(ProcessInfo.processInfo.operatingSystemVersionString) device=\(WhisperKit.deviceName())")
        XCTAssertGreaterThan(samples.count, 16_000, "The real speech fixture must contain decoded audio")
        XCTAssertGreaterThan(peak, 0.01, "The real speech fixture must not decode as silence")
        try await ModelManager.shared.downloadModel(.base)
        let service = LocalWhisperService.shared
        for run in 0..<2 {
            let start = ContinuousClock.now
            let text = try await service.transcribe(audioFileURL: audio, model: .base)
            let words = text.lowercased()
            assertSpeechFixture(text)
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
        try WhisperFixtureDiagnostics.describe(reference)
        try await WhisperFixtureDiagnostics.describeFeatures(reference, audio: audio)
        reference.textDecoder.logitsFilters = [WhisperFixtureDiagnostics()]
        let results = try await reference.transcribe(audioPath: audio.path)
        assertSpeechFixture(results.map { $0.text }.joined(separator: " "))
        for result in results {
            print("REAL_WHISPER_CPU_ONLY language=\(result.language) text=\(result.text)")
            print("REAL_WHISPER_CPU_ONLY tokens=\(result.segments.flatMap { $0.tokens })")
            for segment in result.segments {
                print("REAL_WHISPER_SEGMENT temperature=\(segment.temperature) logprob=\(segment.avgLogprob) noSpeech=\(segment.noSpeechProb)")
            }
        }
    }

    func testWhisperIncrementalLoadingPreservesShortSpeech() async throws {
        try requireRealEngines()
        let audio = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        try await ModelManager.shared.downloadModel(.base)
        let path = try XCTUnwrap(WhisperKitStorage.localModelPath(for: .base))
        let engine = try await WhisperKit(WhisperKitConfig(modelFolder: path, download: false))
        try WhisperFixtureDiagnostics.describe(engine)
        try await WhisperFixtureDiagnostics.describeFeatures(engine, audio: audio)
        engine.textDecoder.logitsFilters = [WhisperFixtureDiagnostics()]
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = nil
        let full = try await engine.transcribe(
            audioPath: audio.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .fullFile), decodeOptions: options)
        let incremental = try await engine.transcribe(
            audioPath: audio.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental), decodeOptions: options)
        let reference = full.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = incremental.map { $0.text }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        assertSpeechFixture(reference)
        assertSpeechFixture(actual)
        XCTAssertEqual(actual, reference)
        print("REAL_WHISPER_LOADING_PARITY transcript=\(actual)")
    }

    private func assertSpeechFixture(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        XCTAssertGreaterThanOrEqual(words.intersection(["quick", "brown", "fox", "lazy", "dog"]).count,
                                    4, text, file: file, line: line)
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
        // Own the worker for this fixture. Leaving the shared daemon idle keeps
        // Foundation's serial AsyncBytes reader occupied and prevents the next
        // fixture's independently owned daemon from receiving its responses.
        let daemon = MLDaemonManager()
        addTeardownBlock { await daemon.shutdown() }
        let service = MLXCorrectionService(daemon: daemon)
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
