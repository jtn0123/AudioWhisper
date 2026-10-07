import XCTest
@testable import AudioWhisper

/// The current larger editors need a provisioned Apple Silicon Mac. Kept
/// distinct from the 7 GB hosted nightly's lightweight inference fixtures.
@MainActor
final class CurrentWritingModelFixtureTests: XCTestCase {
    func testProductionCleanupWarmReuseAndSwitchingAcrossCurrentQwenModels() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["RUN_CURRENT_MODELS"] == "1",
                          "Run scripts/test-current-models.sh on a provisioned Apple Silicon Mac")
        XCTAssertTrue(Arch.isAppleSilicon, "Current MLX models require Apple Silicon")
        XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.physicalMemory, 32 * 1_024 * 1_024 * 1_024,
                                    "The complete Qwen 3.8 fixture requires at least 32 GB unified memory")
        guard Arch.isAppleSilicon, ProcessInfo.processInfo.physicalMemory >= 32 * 1_024 * 1_024 * 1_024 else { return }
        let balanced = "mlx-community/Qwen3.5-9B-4bit"
        let larger = "leonsarmiento/Qwen3.8-27B-3bit-mlx"
        let daemon = MLDaemonManager()
        addTeardownBlock { await daemon.shutdown() }
        let python = try await UvBootstrap.ensureVenv()
        let warmPython = try await UvBootstrap.ensureVenv()
        XCTAssertEqual(python, warmPython, "Reuse the already prepared runtime")
        let service = SemanticCorrectionService(mlxService: MLXCorrectionService(daemon: daemon))
        for (run, repo) in [balanced, balanced, larger, larger, balanced].enumerated() {
            let manager = MLXModelManager.shared
            if !manager.isModelCachedOnDisk(repo: repo) { await manager.downloadModel(repo) }
            XCTAssertTrue(manager.isModelCachedOnDisk(repo: repo), manager.downloadProgress[repo] ?? repo)
            let start = ContinuousClock.now
            let outcome = await service.correctWithOutcome(
                text: "Their going to the store tomorow.", providerUsed: .parakeet, mode: .localMLX, modelRepo: repo)
            guard case .applied(let corrected) = outcome else {
                XCTFail("Real production cleanup must succeed, rather than returning a fallback: \(outcome)")
                continue
            }
            XCTAssertNotEqual(corrected, "Their going to the store tomorow.")
            XCTAssertTrue(corrected.lowercased().contains("tomorrow"), corrected)
            XCTAssertTrue(corrected.lowercased().contains("store"), corrected)
            XCTAssertFalse(corrected.contains("<think>"), corrected)
            XCTAssertLessThan(corrected.count, 100, "Return an edited sentence, not commentary")
            print("REAL_CURRENT_CORRECTION run=\(run) repo=\(repo) pin=\(ModelPins.revision(for: repo) ?? "missing") "
                  + "elapsed=\(start.duration(to: .now)) output=\(corrected)")
        }
    }
}
