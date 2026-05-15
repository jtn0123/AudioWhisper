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
}

/// Sendable holder for a `Result` captured from a completion callback.
private actor ResultBox {
    private(set) var value: Result<Data, Error>?
    func set(_ result: Result<Data, Error>) { value = result }
}
