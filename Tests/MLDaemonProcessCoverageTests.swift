import XCTest
@testable import AudioWhisper

/// Coverage tests for `MLDaemonManager` and `MLDaemonManager+Process`.
///
/// Exercises pure JSON-RPC plumbing and lifecycle helpers that do not need a
/// live subprocess: response routing in `handle(line:)`, pending-request
/// completion, pipe teardown, restart-limit enforcement, and error mapping.
final class MLDaemonProcessCoverageTests: XCTestCase {
    private let manager = MLDaemonManager.shared

    override func setUp() async throws {
        try await super.setUp()
        await manager.resetForTesting()
    }

    override func tearDown() async throws {
        await manager.resetForTesting()
        try await super.tearDown()
    }

    // MARK: - handle(line:) routing

    func testHandleRoutesSuccessResultToPendingRequest() async {
        let received = ResultBox()
        await manager.injectPending(id: 7) { result in
            Task { await received.set(result) }
        }

        await manager.handle(line: #"{"jsonrpc":"2.0","id":7,"result":{"pong":true}}"#)

        // Allow the completion's detached Task to run.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let value = await received.value
        switch value {
        case .success(let data):
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            XCTAssertEqual(json?["pong"] as? Bool, true)
        default:
            XCTFail("Expected success result, got \(String(describing: value))")
        }
    }

    func testHandleRoutesErrorObjectAsRemoteError() async {
        let received = ResultBox()
        await manager.injectPending(id: 11) { result in
            Task { await received.set(result) }
        }

        await manager.handle(line: #"{"jsonrpc":"2.0","id":11,"error":{"message":"boom"}}"#)

        try? await Task.sleep(nanoseconds: 50_000_000)
        let value = await received.value
        switch value {
        case .failure(let error):
            guard case MLDaemonError.remoteError(let message) = error else {
                return XCTFail("Expected remoteError, got \(error)")
            }
            XCTAssertEqual(message, "boom")
        default:
            XCTFail("Expected failure, got \(String(describing: value))")
        }
    }

    func testHandleMissingResultProducesInvalidResponse() async {
        let received = ResultBox()
        await manager.injectPending(id: 13) { result in
            Task { await received.set(result) }
        }

        await manager.handle(line: #"{"jsonrpc":"2.0","id":13}"#)

        try? await Task.sleep(nanoseconds: 50_000_000)
        let value = await received.value
        switch value {
        case .failure(let error):
            guard case MLDaemonError.invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        default:
            XCTFail("Expected failure, got \(String(describing: value))")
        }
    }

    func testHandleIgnoresMalformedJSON() async {
        // No pending requests; a malformed line must be tolerated without crash.
        await manager.handle(line: "this is not json")
        await manager.handle(line: #"{"no":"id field"}"#)
        let count = await manager.pendingCountForTesting()
        XCTAssertEqual(count, 0)
    }

    func testHandleIgnoresUnknownRequestID() async {
        // A response for an id with no pending entry is dropped silently.
        await manager.handle(line: #"{"id":999,"result":{}}"#)
        let count = await manager.pendingCountForTesting()
        XCTAssertEqual(count, 0)
    }

    // MARK: - completeAllPending

    func testCompleteAllPendingFailsEveryEntryAndClearsMap() async {
        let receivedA = ResultBox()
        let receivedB = ResultBox()
        await manager.injectPending(id: 1) { result in Task { await receivedA.set(result) } }
        await manager.injectPending(id: 2) { result in Task { await receivedB.set(result) } }

        await manager.completeAllPending(with: MLDaemonError.daemonUnavailable("teardown"))

        try? await Task.sleep(nanoseconds: 50_000_000)
        let count = await manager.pendingCountForTesting()
        XCTAssertEqual(count, 0, "completeAllPending must clear the pending map")

        for box in [receivedA, receivedB] {
            let value = await box.value
            guard case .failure = value else {
                return XCTFail("Each pending request should be failed")
            }
        }
    }

    // MARK: - closePipes / lifecycle helpers

    func testClosePipesIsSafeWhenNoPipesExist() async {
        // Calling closePipes() on a fresh manager (no process) must not crash.
        await manager.closePipes()
        let running = await manager.isProcessRunningForTesting()
        XCTAssertFalse(running)
    }

    func testShutdownIsIdempotentWithoutProcess() async {
        await manager.shutdown()
        await manager.shutdown()
        let running = await manager.isProcessRunningForTesting()
        XCTAssertFalse(running)
    }

    func testHandleStdoutReaderErrorWhileShuttingDownIsSilent() async {
        // Should not crash regardless of shutting-down state.
        await manager.handleStdoutReaderError(MLDaemonError.timeout)
    }

    // MARK: - processTerminated restart limit

    func testProcessTerminatedRespectsRestartLimit() async {
        // Drive restartAttempts to the limit, then a termination should not
        // attempt a further restart (it would throw scriptNotFound otherwise).
        await manager.bumpRestartAttemptsToLimitForTesting()
        await manager.processTerminated(exitCode: 1)
        // No assertion beyond "did not hang / crash"; the restart-limit guard
        // path is exercised. A surviving call confirms graceful handling.
        let running = await manager.isProcessRunningForTesting()
        XCTAssertFalse(running)
    }

    // MARK: - resolvedScript

    func testResolvedScriptUsesTestOverride() async throws {
        let fakeScript = URL(fileURLWithPath: "/tmp/fake_ml_daemon.py")
        await manager.setTestOverrides(python: nil, script: fakeScript)
        let resolved = try await manager.resolvedScriptForTesting()
        XCTAssertEqual(resolved, fakeScript)
    }

    // MARK: - ensureDaemonRunning guards

    func testEnsureDaemonRunningThrowsWhenShuttingDown() async {
        await manager.markShuttingDownForTesting()
        do {
            try await manager.ensureDaemonRunning()
            XCTFail("Expected daemonUnavailable while shutting down")
        } catch {
            guard case MLDaemonError.daemonUnavailable = error else {
                return XCTFail("Expected daemonUnavailable, got \(error)")
            }
        }
    }

    func testEnsureDaemonRunningThrowsWhenRestartLimitReached() async {
        await manager.bumpRestartAttemptsToLimitForTesting()
        do {
            try await manager.ensureDaemonRunning()
            XCTFail("Expected restartLimitReached")
        } catch {
            guard case MLDaemonError.restartLimitReached = error else {
                return XCTFail("Expected restartLimitReached, got \(error)")
            }
        }
    }

    // MARK: - Crash-loop guard (audit #8)

    /// `startProcess` must count EVERY spawn attempt — restart or not — toward
    /// the limit, and never reset the counter to 0 on a fresh (non-restart)
    /// spawn. Otherwise a daemon that crashes on every request is respawned
    /// forever. We point python at a non-existent path so `proc.run()` throws
    /// without spawning a real process, but the counter still increments.
    func testStartProcessCountsEverySpawnAndTripsRestartLimit() async {
        let fakeScript = URL(fileURLWithPath: "/tmp/fake_ml_daemon_\(UUID().uuidString).py")
        let missingPython = URL(fileURLWithPath: "/nonexistent/python-\(UUID().uuidString)")
        await manager.setTestOverrides(python: missingPython, script: fakeScript)

        // Three spawn attempts are permitted (maxRestartAttempts == 3); each
        // fails to launch but is counted. The fourth must trip the limit.
        var sawRestartLimit = false
        for attempt in 1...4 {
            do {
                try await manager.startProcess(isRestart: false)
                XCTFail("Spawn \(attempt) should not have succeeded with a missing python")
            } catch MLDaemonError.restartLimitReached {
                sawRestartLimit = true
                XCTAssertEqual(attempt, 4, "Limit should trip on the 4th attempt, not earlier")
            } catch {
                // daemonUnavailable from a failed proc.run() — expected for 1...3.
                XCTAssertLessThanOrEqual(attempt, 3)
            }
        }
        XCTAssertTrue(sawRestartLimit, "A repeatedly-crashing daemon must eventually trip restartLimitReached")

        let count = await manager.restartAttemptsForTesting()
        let limit = await manager.maxRestartAttempts
        XCTAssertGreaterThanOrEqual(count, limit,
                                    "Fresh spawns must NOT reset the crash-loop counter")
    }

    /// A successful daemon reply resets the crash-loop counter (audit #8): the
    /// daemon has proven healthy, so transient earlier restarts are forgiven.
    func testSuccessfulReplyResetsRestartCounter() async {
        await manager.setRestartAttemptsForTesting(2)
        await manager.injectPending(id: 42) { _ in }
        await manager.handle(line: #"{"jsonrpc":"2.0","id":42,"result":{"pong":true}}"#)

        let count = await manager.restartAttemptsForTesting()
        XCTAssertEqual(count, 0, "A successful reply should clear the restart counter")
    }

    /// `markDaemonStableIfHealthy` resets the counter only for the live daemon.
    func testStabilityCheckIgnoresStaleProcessIdentity() async {
        await manager.setRestartAttemptsForTesting(2)
        // A process that is not the manager's current daemon must be ignored.
        let unrelated = Process()
        await manager.markDaemonStableIfHealthy(unrelated)
        let count = await manager.restartAttemptsForTesting()
        XCTAssertEqual(count, 2, "A stale/unowned process must not reset the counter")
    }

    // MARK: - Shutdown re-check (audit #25)

    /// If `shutdown()` runs while `startProcess` is awaiting an async hop, the
    /// re-check before `proc.run()` must abort the spawn rather than leak an
    /// unowned daemon.
    func testStartProcessAbortsWhenShuttingDown() async {
        let fakeScript = URL(fileURLWithPath: "/tmp/fake_ml_daemon_\(UUID().uuidString).py")
        await manager.setTestOverrides(python: URL(fileURLWithPath: "/usr/bin/true"), script: fakeScript)
        await manager.markShuttingDownForTesting()

        do {
            try await manager.startProcess(isRestart: false)
            XCTFail("startProcess must abort while shutting down")
        } catch {
            guard case MLDaemonError.daemonUnavailable = error else {
                return XCTFail("Expected daemonUnavailable, got \(error)")
            }
        }
        let running = await manager.isProcessRunningForTesting()
        XCTAssertFalse(running, "No daemon should be spawned during shutdown")
    }

    // MARK: - Dead-daemon teardown (audit #23)

    /// `teardownDeadDaemon` fails pending requests and clears the process
    /// handle so a later `ensureDaemonRunning` can spawn fresh.
    func testTeardownDeadDaemonFailsPendingAndClearsProcess() async {
        let received = ResultBox()
        await manager.injectPending(id: 5) { result in
            Task { await received.set(result) }
        }

        await manager.teardownDeadDaemon()

        try? await Task.sleep(nanoseconds: 50_000_000)
        let value = await received.value
        guard case .failure = value else {
            return XCTFail("Pending request should be failed when the daemon is torn down")
        }
        let running = await manager.isProcessRunningForTesting()
        XCTAssertFalse(running)
        let count = await manager.pendingCountForTesting()
        XCTAssertEqual(count, 0)
    }
}

/// Sendable holder for a `Result` captured from a completion callback.
private actor ResultBox {
    private(set) var value: Result<Data, Error>?
    func set(_ result: Result<Data, Error>) { value = result }
}

// MARK: - stderr Sanitisation (E2)

/// `ml_daemon` stderr used to be logged at `privacy: .public`. The daemon's
/// `correct` method receives the full transcript, so a traceback can carry user
/// speech into the unified log. These tests pin the sanitiser that now decides
/// what is safe to expose publicly.
final class MLDaemonStderrSanitisationTests: XCTestCase {

    /// The load-bearing case: a traceback whose exception message and echoed
    /// source line both contain the user's dictated text. Nothing but the
    /// exception type may survive into the public summary.
    func testTranscriptTextNeverReachesThePublicSummary() {
        let secret = "my bank password is hunter2 and my address is 42 Elm Street"
        let stderr = """
        Traceback (most recent call last):
          File "/Users/someone/Library/Application Support/AudioWhisper/ml_daemon.py", line 88, in correct
            result = model.generate(prompt + "\(secret)")
          File "/opt/venv/lib/python3.11/site-packages/mlx_lm/utils.py", line 412, in generate
            raise ValueError(f"context overflow while correcting: \(secret)")
        ValueError: context overflow while correcting: \(secret)
        """

        let summary = MLDaemonManager.pythonExceptionSummary(in: stderr)

        XCTAssertEqual(summary, "ValueError")
        XCTAssertFalse(
            summary.contains("hunter2"),
            "Transcript text leaked into the public log summary: \(summary)"
        )
        XCTAssertFalse(
            summary.contains("Elm Street"),
            "Transcript text leaked into the public log summary: \(summary)"
        )
        XCTAssertFalse(
            summary.contains("/Users/someone"),
            "Home-directory path leaked into the public log summary: \(summary)"
        )
    }

    func testRecognisesCommonExceptionTypes() {
        XCTAssertEqual(
            MLDaemonManager.pythonExceptionSummary(in: "ModuleNotFoundError: No module named 'mlx_lm'"),
            "ModuleNotFoundError"
        )
        XCTAssertEqual(
            MLDaemonManager.pythonExceptionSummary(in: "KeyboardInterrupt: "),
            "KeyboardInterrupt"
        )
        XCTAssertEqual(
            MLDaemonManager.pythonExceptionSummary(in: "SystemExit: 1"),
            "SystemExit"
        )
    }

    /// Dotted module paths are reduced to the bare class name.
    func testDottedExceptionPathReportsBareClassName() {
        XCTAssertEqual(
            MLDaemonManager.pythonExceptionSummary(in: "mlx.core.MLXRuntimeError: metal allocation failed"),
            "MLXRuntimeError"
        )
    }

    /// A chained traceback names several types; order is preserved, duplicates
    /// collapse, and the list is capped.
    func testChainedExceptionsAreDedupedAndCapped() {
        let stderr = """
        ValueError: first
        During handling of the above exception, another exception occurred:
        RuntimeError: second
        ValueError: duplicate of the first
        TypeError: third
        OSError: fourth
        KeyError: fifth should be dropped by the cap
        """

        let types = MLDaemonManager.pythonExceptionTypes(in: stderr)
        XCTAssertEqual(types, ["ValueError", "RuntimeError", "TypeError", "OSError", "KeyError"])

        let summary = MLDaemonManager.pythonExceptionSummary(in: stderr)
        XCTAssertEqual(summary, "ValueError, RuntimeError, TypeError, OSError")
        XCTAssertFalse(summary.contains("KeyError"), "Cap of \(MLDaemonManager.maxSummaryTypes) not applied")
    }

    /// An indented source echo can itself look like `word: text`. Indented lines
    /// are traceback frames, never the exception terminator, so they must not be
    /// mined for type names — that is exactly how payload would escape.
    func testIndentedSourceEchoesAreIgnored() {
        let stderr = """
          File "/tmp/x.py", line 3, in correct
            Warning: the user said something private here
        """
        XCTAssertEqual(MLDaemonManager.pythonExceptionSummary(in: stderr), "unclassified")
    }

    /// Progress chatter and warnings that aren't exception terminators produce
    /// no false classification.
    func testNonExceptionOutputIsUnclassified() {
        XCTAssertEqual(MLDaemonManager.pythonExceptionSummary(in: ""), "unclassified")
        XCTAssertEqual(
            MLDaemonManager.pythonExceptionSummary(in: "Fetching 12 files: 100%|██████| 12/12"),
            "unclassified"
        )
        XCTAssertEqual(
            MLDaemonManager.pythonExceptionSummary(in: "loading model: mlx-community/Qwen3-1.7B-4bit"),
            "unclassified"
        )
    }
}
