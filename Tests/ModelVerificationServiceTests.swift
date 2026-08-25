import XCTest
@testable import AudioWhisper

/// Tests for the model-verification output parsing and result wording.
///
/// Audit item C4. This logic used to exist twice, verbatim, inside SwiftUI view
/// files — `DashboardProviders+Parakeet` (0.0% coverage) and
/// `DashboardCorrection+Verify` (part of a file at 9.5%). Both spawned a
/// process, parsed JSON from stdout, and mapped an exit status to a message,
/// and neither was reachable from a test because it lived on a `View`.
///
/// The `Process` plumbing itself is not tested here — that needs a real Python
/// environment and is covered by the nightly end-to-end job. What is tested is
/// everything that decides what the user actually sees.
final class ModelVerificationServiceTests: XCTestCase {

    // MARK: - stdout parsing

    func testLastJSONMessageOnStdoutWins() {
        var collector = VerificationOutputCollector()
        collector.ingestStdout(#"{"message": "Resolving files"}"#)
        collector.ingestStdout(#"{"message": "Loading weights"}"#)

        XCTAssertEqual(collector.lastStdoutMessage, "Loading weights")
    }

    /// A pipe read can deliver several lines at once.
    func testMultipleLinesInOneChunkAreAllProcessed() {
        var collector = VerificationOutputCollector()
        collector.ingestStdout("""
        {"message": "first"}
        {"message": "second"}
        {"message": "third"}
        """)

        XCTAssertEqual(collector.lastStdoutMessage, "third")
    }

    /// The counterpart to the B2 fix: unstructured output must not become the
    /// message shown to the user.
    func testNonJSONStdoutIsIgnored() {
        var collector = VerificationOutputCollector()
        collector.ingestStdout(#"{"message": "real progress"}"#)
        collector.ingestStdout("Fetching 12 files:  8%|▊         | 1/12 [00:00<00:03,  3.02it/s]")
        collector.ingestStdout("some bare log line")

        XCTAssertEqual(collector.lastStdoutMessage, "real progress",
                       "unstructured output must not overwrite a real message")
    }

    func testJSONWithoutAMessageKeyIsIgnored() {
        var collector = VerificationOutputCollector()
        collector.ingestStdout(#"{"message": "kept"}"#)
        collector.ingestStdout(#"{"status": "working"}"#)

        XCTAssertEqual(collector.lastStdoutMessage, "kept")
    }

    // MARK: - stderr

    func testBlankStderrDoesNotOverwriteARealError() {
        var collector = VerificationOutputCollector()
        collector.ingestStderr("ModuleNotFoundError: no module named mlx")
        collector.ingestStderr("   \n  ")

        XCTAssertEqual(collector.lastStderrMessage, "ModuleNotFoundError: no module named mlx")
    }

    func testStderrIsTrimmed() {
        var collector = VerificationOutputCollector()
        collector.ingestStderr("  boom  \n")

        XCTAssertEqual(collector.lastStderrMessage, "boom")
    }

    // MARK: - Result wording

    func testSuccessUsesTheLastStdoutMessage() {
        var collector = VerificationOutputCollector()
        collector.ingestStdout(#"{"message": "Model verified against cache"}"#)

        let result = collector.result(terminationStatus: 0, successFallback: "Model verified")

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.message, "Model verified against cache")
    }

    func testSuccessWithNoStdoutFallsBackToTheSuppliedLabel() {
        let collector = VerificationOutputCollector()

        let result = collector.result(terminationStatus: 0, successFallback: "Model verified")

        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.message, "Model verified")
    }

    func testFailurePrefersStdoutDetail() {
        var collector = VerificationOutputCollector()
        collector.ingestStdout(#"{"message": "model files missing"}"#)
        collector.ingestStderr("Traceback (most recent call last):")

        let result = collector.result(terminationStatus: 1, successFallback: "Model verified")

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, "Verification failed: model files missing")
    }

    func testFailureFallsBackToStderrWhenStdoutIsSilent() {
        var collector = VerificationOutputCollector()
        collector.ingestStderr("ModuleNotFoundError: no module named mlx")

        let result = collector.result(terminationStatus: 1, successFallback: "Model verified")

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, "Verification failed: ModuleNotFoundError: no module named mlx")
    }

    /// The stranded-spinner case: a failure with no output at all must still
    /// produce a concrete message, never leave "Checking model…" on screen.
    func testSilentFailureStillReportsSomethingConcrete() {
        let collector = VerificationOutputCollector()

        let result = collector.result(terminationStatus: 1, successFallback: "Model verified")

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, "Verification failed")
        XCTAssertFalse(result.message.isEmpty)
    }

    /// A terminated process (the 180s timeout path) exits non-zero and must be
    /// reported as failure, not success.
    func testTerminatedProcessIsAFailure() {
        var collector = VerificationOutputCollector()
        collector.ingestStdout(#"{"message": "still working"}"#)

        let result = collector.result(terminationStatus: 15, successFallback: "Model verified")

        XCTAssertFalse(result.succeeded,
                       "a non-zero status is a failure even when stdout looked healthy")
        XCTAssertEqual(result.message, "Verification failed: still working")
    }

    // MARK: - Script lookup

    func testMissingScriptThrowsScriptNotFound() async {
        do {
            _ = try await ModelVerificationService.verify(
                scriptName: "definitely_not_a_bundled_script",
                arguments: [],
                pythonPath: "/usr/bin/true",
                successFallback: "ok"
            )
            XCTFail("expected scriptNotFound")
        } catch let error as ModelVerificationError {
            guard case .scriptNotFound(let name) = error else {
                return XCTFail("expected .scriptNotFound, got \(error)")
            }
            XCTAssertEqual(name, "definitely_not_a_bundled_script")
        } catch {
            XCTFail("expected ModelVerificationError, got \(error)")
        }
    }
}
