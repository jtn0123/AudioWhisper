import CoreML
import WhisperKit
import XCTest
@testable import AudioWhisper

/// Actual app factory/service acceptance, distinct from the raw-SDK controls.
@MainActor
final class WhisperProductionAcceptanceTests: XCTestCase {
    func testAInstalledPreparedCacheReportsAnExactIdentityHit() async throws {
        _ = try await fixture()
        guard PreparedWhisperEncoder.Environment.current.applies(to: .base) else {
            throw XCTSkip("The prepared encoder is qualified only for Apple Silicon macOS 15")
        }
        let counter = PreparedCompilationCounter()
        let folder = URL(fileURLWithPath: try XCTUnwrap(WhisperKitStorage.localModelPath(for: .base)))
        let preparer = PreparedWhisperEncoder(compile: { package in
            await counter.increment()
            return try await MLModel.compileModel(at: package)
        })
        let first = try await preparer.prepare(model: .base, folder: folder, compute: .cpuAndNeuralEngine)
        _ = try XCTUnwrap(first, "Restore acceptance requires the qualified prepared encoder")
        let firstCompilations = await counter.value
        let second = try await preparer.prepare(model: .base, folder: folder, compute: .cpuAndNeuralEngine)
        XCTAssertEqual(first, second)
        let totalCompilations = await counter.value
        XCTAssertEqual(totalCompilations, firstCompilations, "A matching validated identity must not recompile")
        if ProcessInfo.processInfo.environment["REQUIRE_PREPARED_CACHE_HIT"] == "true" {
            XCTAssertEqual(firstCompilations, 0, "Restored derived-cache acceptance requires zero compilations")
        }
        print("PRODUCTION_WHISPER_PREPARED firstCompilations=\(firstCompilations) secondCompilations=0")
    }

    func testBaseServiceRecognizesColdWarmAndReloadedModel() async throws {
        let audio = try await fixture()
        let service = LocalWhisperService.shared
        await service.clearCache()
        let preparedRoot = PreparedWhisperEncoder().root
        print("PRODUCTION_WHISPER preparedCachePresentBefore=\(FileManager.default.fileExists(atPath: preparedRoot.path))")
        for run in 0..<3 {
            if run == 2 { await service.clearCache() }
            let start = ContinuousClock.now
            let text = try await service.transcribe(audioFileURL: audio, model: .base)
            assertSpeech(text)
            print("PRODUCTION_WHISPER run=\(run) elapsed=\(start.duration(to: .now)) text=\(text)")
        }
        try await service.verifyModel(.base)
        await service.clearCache()
    }

    func testFullAndIncrementalLoadingUseTheProductionEncoder() async throws {
        let audio = try await fixture()
        let folder = try XCTUnwrap(WhisperKitStorage.localModelPath(for: .base))
        let engine = try await WhisperEngineFactory.make(model: .base, folder: folder)
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = nil
        let full = try await engine.transcribe(audioPath: audio.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .fullFile), decodeOptions: options)
        let incremental = try await engine.transcribe(audioPath: audio.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental), decodeOptions: options)
        let expected = full.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let actual = incremental.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        assertSpeech(expected)
        assertSpeech(actual)
        XCTAssertEqual(actual, expected)
        print("PRODUCTION_WHISPER_LOADING full=\(expected) incremental=\(actual)")
    }

    func testPreparedEncoderPersistsAfterStagingIsRemoved() async throws {
        _ = try await fixture()
        let folder = URL(fileURLWithPath: try XCTUnwrap(WhisperKitStorage.localModelPath(for: .base)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // Exercise persistent packaging even on a newer development OS. This
        // does not qualify macOS 15; its separate hosted run uses the real policy.
        let environment = PreparedWhisperEncoder.Environment(
            major: 15, appleSilicon: true, build: ProcessInfo.processInfo.operatingSystemVersionString)
        let preparer = PreparedWhisperEncoder(root: root, environment: environment)
        let first = try await preparer.prepare(model: .base, folder: folder, compute: .cpuAndNeuralEngine)
        let prepared = try XCTUnwrap(first)
        try PreparedWhisperEncoder.validateModel(prepared, compute: .cpuAndNeuralEngine)
        let second = try await preparer.prepare(model: .base, folder: folder, compute: .cpuAndNeuralEngine)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
        print("PRODUCTION_WHISPER_PREPARED persisted=true validatedCacheHit=true")
    }

    private func fixture() async throws -> URL {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_E2E"] == "1", "Opt-in real model acceptance")
        try XCTSkipUnless(Arch.isAppleSilicon, "Qualified hosted acceptance uses Apple Silicon")
        try await ModelManager.shared.downloadModel(.base)
        return try XCTUnwrap(Bundle.module.url(forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
    }

    private func assertSpeech(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        XCTAssertGreaterThanOrEqual(words.intersection(["quick", "brown", "fox", "lazy", "dog"]).count,
                                    4, text, file: file, line: line)
    }
}

private actor PreparedCompilationCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}
