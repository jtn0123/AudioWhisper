import XCTest
@testable import AudioWhisper

/// End-to-end integration test that exercises the real Parakeet/MLX subprocess
/// flow: venv bootstrap -> model load -> daemon spawn -> JSON-RPC -> transcription.
///
/// This test is OPT-IN. It requires:
///   - Apple Silicon (Parakeet-MLX requires arm64)
///   - Network access on first run (downloads ~2.5 GB model)
///   - One of:
///       * `RUN_E2E=1` — the new generic e2e gate (preferred), or
///       * `RUN_PARAKEET_E2E=1` — backwards-compatible alias
///
/// The test self-bootstraps the model if it isn't cached, so nightly CI can
/// run it from a clean machine. Subsequent runs reuse the HuggingFace cache.
///
/// Run from the command line:
///   RUN_E2E=1 swift test --filter ParakeetEndToEndTests
///
/// CI runs this nightly (.github/workflows/nightly.yml, RUN_E2E=1) and on
/// demand via workflow_dispatch; per-PR runs skip it via XCTSkip below, because
/// a cold run downloads a ~2.5 GB model.
final class ParakeetEndToEndTests: XCTestCase {

    @MainActor
    func test_e2e_transcribeShortClip() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_E2E"] == "1"
                || ProcessInfo.processInfo.environment["RUN_PARAKEET_E2E"] == "1",
            "Parakeet E2E test is gated. Set RUN_E2E=1 (or RUN_PARAKEET_E2E=1) to run."
        )

        try XCTSkipUnless(
            Arch.isAppleSilicon,
            "Parakeet requires Apple Silicon."
        )

        // Not test_audio.wav: that is a 0.1 s 440 Hz tone, for which an empty
        // transcript is the CORRECT answer. This test used it until it first
        // ran to completion and failed on exactly that. speech_sample.wav is
        // `say -v Samantha` reading the sentence below, at 16 kHz mono.
        guard let fixtureURL = Bundle.module.url(
            forResource: "speech_sample",
            withExtension: "wav",
            subdirectory: "Resources"
        ) else {
            XCTFail("Missing Tests/Resources/speech_sample.wav fixture")
            return
        }

        // Step 1: Ensure the model is on disk. MLXModelManager is the
        // canonical entry point used by the in-app Settings flow; calling it
        // here means a fresh CI box can run this test end-to-end without a
        // manual pre-cache step. `ensureParakeetModel()` short-circuits when
        // the cache is already populated, and otherwise returns only once the
        // download has finished.
        let manager = MLXModelManager.shared
        let repo = MLXModelManager.parakeetRepo
        await manager.ensureParakeetModel()

        // A failed download is recorded in `downloadProgress`, not thrown.
        // Surface it here: without this, every cause (no network, no uv
        // project, a broken script) reached the log as the same bare
        // `modelNotReady` from step 2, which is how this test failed every
        // night for six weeks without saying why.
        guard manager.isModelCachedOnDisk(repo: repo) else {
            let status = manager.downloadProgress[repo] ?? "no status was recorded"
            XCTFail("\(repo) is not on disk after ensureParakeetModel(): \(status)")
            return
        }

        // Step 2: Warm up the daemon and verify the cache is consistent.
        let service = ParakeetService.shared
        try await service.validateSetup()

        // Step 3: Transcribe the fixture.
        let text = try await service.transcribe(audioFileURL: fixtureURL)

        // The fixture says "The quick brown fox jumps over the lazy dog."
        // Checked by words rather than exact text, so casing and punctuation
        // cannot fail it, but loosely enough (4 of 5) that one misheard word
        // does not either. The model revision is pinned (ModelPins), so the
        // output only changes when someone bumps the pin.
        let heard = Set(
            text.lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }
        )
        let expected = ["quick", "brown", "fox", "lazy", "dog"]
        let matched = expected.filter(heard.contains)
        XCTAssertGreaterThanOrEqual(
            matched.count, 4,
            "Transcript \"\(text)\" matched only \(matched) of \(expected)"
        )
    }
}
