import XCTest
@testable import AudioWhisper

/// Opt-in real subprocess inference, with explicit model IDs rather than the
/// user's selection. Nightly covers English, warm reuse, switching and Spanish.
@MainActor
final class ParakeetEndToEndTests: XCTestCase {
    private func requireRealEngines() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_E2E"] == "1"
                || ProcessInfo.processInfo.environment["RUN_PARAKEET_E2E"] == "1",
            "Set RUN_E2E=1 (or RUN_PARAKEET_E2E=1) for real Parakeet inference")
        try XCTSkipUnless(Arch.isAppleSilicon)
    }

    func testExplicitEnglishModelsWarmReuseAndSwitching() async throws {
        try requireRealEngines()
        let audio = try fixture("speech_sample")
        let daemon = MLDaemonManager()
        addTeardownBlock { await daemon.shutdown() }
        let service = ParakeetService(daemon: daemon)
        for model in [ParakeetModel.v2English, .v2English, .v3Multilingual, .v3Multilingual, .v2English] {
            try await ensureModel(model)
            let start = ContinuousClock.now
            let text = try await service.transcribe(audioFileURL: audio, pythonPath: nil, model: model)
            assertWords(text, expected: ["quick", "brown", "fox", "lazy", "dog"], minimum: 4)
            print("REAL_PARAKEET repo=\(model.rawValue) pin=\(ModelPins.revision(for: model.rawValue) ?? "missing") "
                  + "elapsed=\(start.duration(to: .now)) transcript=\(text)")
        }
    }

    func testV3TranscribesSpanishWithoutAnEnglishTranslation() async throws {
        try requireRealEngines()
        try await ensureModel(.v3Multilingual)
        let daemon = MLDaemonManager()
        addTeardownBlock { await daemon.shutdown() }
        let text = try await ParakeetService(daemon: daemon).transcribe(
            audioFileURL: fixture("speech_spanish"), pythonPath: nil, model: .v3Multilingual)
        assertWords(text, expected: ["mañana", "visitar", "parque", "agua", "cámara"], minimum: 4)
        print("REAL_PARAKEET language=Spanish repo=\(ParakeetModel.v3Multilingual.rawValue) transcript=\(text)")
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Resources"))
    }

    private func ensureModel(_ model: ParakeetModel) async throws {
        let manager = MLXModelManager.shared
        if !manager.isModelCachedOnDisk(repo: model.rawValue) { await manager.downloadParakeetModel(repo: model.rawValue) }
        XCTAssertTrue(manager.isModelCachedOnDisk(repo: model.rawValue),
                      "\(model.rawValue): \(manager.downloadProgress[model.rawValue] ?? "No download status")")
    }

    private func assertWords(_ text: String, expected: [String], minimum: Int) {
        let heard = Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        XCTAssertGreaterThanOrEqual(expected.filter(heard.contains).count, minimum, text)
    }
}
