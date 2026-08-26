import XCTest

/// Source-level guards on the bundled MLX correction Python.
///
/// These previously read `Sources/mlx_semantic_correct.py`, a standalone script
/// that `ResourceLocator` never looked up and nothing ever executed —
/// correction runs through `ml_daemon.py` → `ml/rpc.py` → `ml/correction.py`.
/// The script has been removed, so the guards are retargeted at the live
/// package. Two of the three behaviours they protected exist there; the third
/// (`return 5` / `dependency_missing`) described the deleted script's
/// return-code structure, which the daemon architecture does not use.
///
/// Grepping source text is a weak form of test, but it is the right one here:
/// the alternative is running MLX, which needs a multi-gigabyte model and is
/// covered by the nightly end-to-end job.
final class MLXScriptTests: XCTestCase {

    private func sourceOfLiveMLPackage() throws -> [(name: String, content: String)] {
        let mlDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()  // drop file name
            .deletingLastPathComponent()  // drop Tests directory
            .appendingPathComponent("Sources/ml")

        let files = try FileManager.default.contentsOfDirectory(at: mlDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "py" }
        XCTAssertFalse(files.isEmpty, "Sources/ml should contain the live correction package")

        return try files.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// Generation must stay capped. An uncapped `max_tokens` on a local model is
    /// how a correction pass turns into a multi-minute stall.
    func testGenerationIsCappedAt4096Tokens() throws {
        let sources = try sourceOfLiveMLPackage()
        let capped = sources.contains { $0.content.contains("min(4096") }

        XCTAssertTrue(capped, "the live correction path must cap generation at 4096 tokens")
    }

    /// Audit #28. `print` returns None, and `sys.exit(None)` exits **0** — so
    /// `return print(...)` on a failure path reports success. This scans the
    /// whole live package rather than one file, which is a stronger guard than
    /// the original: the bug is a Python foot-gun, not a property of one script.
    func testNoFailurePathReturnsPrint() throws {
        let sources = try sourceOfLiveMLPackage()

        for (name, content) in sources {
            XCTAssertFalse(
                content.contains("return print("),
                "\(name): `return print(...)` returns None -> sys.exit(0), masking failure"
            )
        }
    }

    /// The offline-load failure must still be reported in words the caller can
    /// surface; `MLXCorrectionService` and the Dashboard both key off it.
    func testOfflineLoadFailureIsStillReported() throws {
        let sources = try sourceOfLiveMLPackage()
        let reports = sources.contains { $0.content.contains("MLX model not available offline") }

        XCTAssertTrue(reports, "the offline-failure message must survive in the live loader")
    }
}
