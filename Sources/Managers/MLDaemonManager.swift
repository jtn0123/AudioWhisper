import Foundation
import os.log

internal enum MLDaemonError: Error, LocalizedError {
    case scriptNotFound
    case daemonUnavailable(String)
    case invalidResponse(String)
    case remoteError(String)
    case restartLimitReached
    case writeFailed
    case timeout

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "ml_daemon.py could not be found"
        case .daemonUnavailable(let reason):
            return "ML daemon unavailable: \(reason)"
        case .invalidResponse(let reason):
            return "Invalid response from ML daemon: \(reason)"
        case .remoteError(let message):
            return "ML daemon error: \(message)"
        case .restartLimitReached:
            return "ML daemon restart limit reached"
        case .writeFailed:
            return "Failed to write request to ML daemon"
        case .timeout:
            return "ML daemon request timed out"
        }
    }
}

internal actor MLDaemonManager {
    static let shared = MLDaemonManager()

    // Note: the storage below is `internal` rather than `private` because the
    // process-lifecycle methods live in `MLDaemonManager+Process.swift`. Swift
    // `private` is file-scoped, so a cross-file extension cannot see it.
    struct PendingRequest {
        let completion: (Result<Data, Error>) -> Void
        /// Hard deadline after which the request is considered abandoned and is
        /// reaped by `sweepExpiredRequests()`. Prevents `pending` from growing
        /// unboundedly if responses get lost.
        let deadline: Date
    }

    let logger = Logger(subsystem: "com.audiowhisper.app", category: "MLDaemon")
    let maxRestartAttempts = 3
    /// Uptime a daemon must accumulate before it's treated as "stable" and the
    /// crash-loop restart counter is reset. See `markDaemonStableIfHealthy`.
    static let stableUptimeSeconds: UInt64 = 10
    private let requestTimeoutSeconds: UInt64 = 60
    /// Hard cap on a single JSON-RPC request payload (M6). Picked at 1 MiB —
    /// large enough for the longest realistic correction/transcription input
    /// but small enough that an oversize string can't DoS the Python daemon
    /// by exhausting memory while it deserializes.
    static let maxRequestBytes: Int = 1 * 1024 * 1024

    var process: Process?
    var stdinPipe: Pipe?
    var stdoutPipe: Pipe?
    var stderrPipe: Pipe?
    var pending: [Int: PendingRequest] = [:]
    private var nextRequestID: Int = 1
    var restartAttempts: Int = 0
    var isShuttingDown = false
    /// True while `startProcess` is between checking for an existing process
    /// and finishing process attachment. Prevents queued `ensureDaemonRunning`
    /// callers from launching a duplicate daemon during an in-flight spawn (H6).
    var isStarting = false
    var stdoutReaderTask: Task<Void, Never>?
    private var pythonExecutable: URL?
    private var scriptLocation: URL?
    private var testResponder: ((MLRPCMethod, JSONValue) throws -> JSONValue)?

    // MARK: - Public API

    func transcribe(repo: String, pcmPath: String) async throws -> String {
        let result: MLRPCResult.Transcribe = try await sendRequest(
            method: .transcribe,
            params: MLRPCParams.Transcribe(repo: repo, pcmPath: pcmPath)
        )
        guard result.success else { throw MLDaemonError.remoteError(result.error ?? "Transcription failed") }
        return result.text
    }

    func correct(repo: String, text: String, prompt: String?) async throws -> String {
        let result: MLRPCResult.Correct = try await sendRequest(
            method: .correct,
            params: MLRPCParams.Correct(repo: repo, text: text, prompt: prompt)
        )
        guard result.success else { throw MLDaemonError.remoteError(result.error ?? "Correction failed") }
        return result.text
    }

    func warmup(type: MLWarmupKind, repo: String) async throws {
        let _: MLRPCResult.Warmup = try await sendRequest(
            method: .warmup,
            params: MLRPCParams.Warmup(type: type, repo: repo)
        )
    }

    func ping() async -> Bool {
        do {
            let result: MLRPCResult.Ping = try await sendRequest(
                method: .ping,
                params: MLRPCParams.Empty?.none
            )
            return result.pong
        } catch {
            logger.error("Ping failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Core JSON-RPC plumbing

    private func sendRequest<Params: Encodable, Response: Decodable>(
        method: MLRPCMethod,
        params: Params?
    ) async throws -> Response {
        if testResponder != nil {
            return try respondFromTestStub(method: method, params: params)
        }
        // Drop any pending entries whose deadline has passed. This is cheap
        // (no separate timer) and guarantees the `pending` map can't grow
        // unboundedly if responses are lost.
        sweepExpiredRequests()
        try await ensureDaemonRunning()

        let requestID = nextRequestID
        nextRequestID += 1

        let request = MLRPCRequest(id: requestID, method: method, params: params)
        let data = try JSONEncoder().encode(request)
        // M6: cap payload size so a multi-MB string can't DoS the Python side.
        if data.count > Self.maxRequestBytes {
            throw MLDaemonError.daemonUnavailable("input too large (max \(Self.maxRequestBytes) bytes)")
        }
        guard let writer = stdinPipe?.fileHandleForWriting else {
            throw MLDaemonError.daemonUnavailable("stdin unavailable")
        }

        // Use withCheckedThrowingContinuation with timeout via Task
        let timeoutNanos = requestTimeoutSeconds * 1_000_000_000

        let deadline = Date().addingTimeInterval(TimeInterval(requestTimeoutSeconds))
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Response, Error>) in
            // Register the pending request BEFORE writing to stdin (audit #24).
            // If the daemon replies faster than we'd otherwise register, the
            // stdout handler would find "no pending request" and drop the
            // reply, leaving the caller to wait the full timeout.
            self.pending[requestID] = PendingRequest(
                completion: { result in
                    switch result {
                    case .success(let responseData):
                        do {
                            let decoded = try JSONDecoder().decode(Response.self, from: responseData)
                            continuation.resume(returning: decoded)
                        } catch {
                            continuation.resume(throwing: MLDaemonError.invalidResponse(error.localizedDescription))
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                },
                deadline: deadline
            )

            // H9: perform the synchronous stdin write OFF the actor. A blocked
            // write (full pipe + stalled daemon) inside actor isolation would
            // prevent `handle(line:)` from running, deadlocking the pair.
            Task.detached { [weak self] in
                do {
                    try writer.write(contentsOf: data)
                    try writer.write(contentsOf: Data([0x0a])) // newline
                } catch {
                    await self?.handleWriteFailure(requestID: requestID, error: error)
                }
            }

            // Start timeout task.
            // SAFETY: Race condition between timeout and response is handled by actor isolation.
            // Since MLDaemonManager is an actor, all accesses to `pending` are serialized.
            // Both the timeout task and handle(line:) use removeValue(forKey:) which returns
            // nil if the key was already removed - ensuring exactly one caller resumes the continuation.
            Task {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                // Atomically check-and-remove: only resume if WE removed it
                // This prevents double-resume if response arrives simultaneously
                if self.pending.removeValue(forKey: requestID) != nil {
                    continuation.resume(throwing: MLDaemonError.timeout)
                }
            }
        }
    }

    /// Routes a request to the injected test stub instead of the subprocess.
    ///
    /// Params are handed over as a decoded `JSONValue` rather than the typed
    /// struct deliberately: a test asserting `params["pcm_path"] == "/tmp/a"`
    /// is checking the WIRE key, which is what the daemon reads. Asserting on
    /// the Swift property name would pass happily through a CodingKey rename
    /// that breaks Python.
    private func respondFromTestStub<Params: Encodable, Response: Decodable>(
        method: MLRPCMethod,
        params: Params?
    ) throws -> Response {
        guard let testResponder else {
            throw MLDaemonError.daemonUnavailable("no test responder")
        }
        let encodedParams = try JSONEncoder().encode(params ?? nil as Params?)
        let decodedParams = (try? JSONDecoder().decode(JSONValue.self, from: encodedParams)) ?? .null
        let resultValue = try testResponder(method, decodedParams)
        do {
            return try JSONDecoder().decode(Response.self, from: JSONEncoder().encode(resultValue))
        } catch {
            throw MLDaemonError.invalidResponse(error.localizedDescription)
        }
    }

    /// Tears down the dead daemon and fails the in-flight request whose
    /// detached stdin write threw. Invoked from the H9 off-actor write path.
    func handleWriteFailure(requestID: Int, error: Error) async {
        logger.error("Failed to write to daemon stdin: \(error.localizedDescription)")
        if let entry = pending.removeValue(forKey: requestID) {
            entry.completion(.failure(MLDaemonError.writeFailed))
        }
        await teardownDeadDaemon()
    }

    /// Removes any pending requests whose deadline has passed, completing each
    /// with `.timeout`. Cheap to call on every new request — keeps `pending`
    /// bounded without a separate timer.
    private func sweepExpiredRequests(now: Date = Date()) {
        let expired = pending.filter { $0.value.deadline < now }
        guard !expired.isEmpty else { return }
        for (id, entry) in expired {
            pending.removeValue(forKey: id)
            entry.completion(.failure(MLDaemonError.timeout))
        }
        logger.error("Reaped \(expired.count, privacy: .public) expired ML daemon request(s)")
    }

    func handle(line: String) {
        guard let data = line.data(using: .utf8) else {
            logger.error("Failed to decode daemon line")
            return
        }
        guard
            let envelope = try? JSONDecoder().decode(MLRPCEnvelope.self, from: data),
            let id = envelope.id
        else {
            // Also the path for rpc.py's parse-failure reply, which carries
            // "id": null because it never got far enough to read one.
            logger.error("Malformed JSON-RPC response")
            return
        }

        guard let pendingRequest = pending.removeValue(forKey: id) else {
            logger.error("No pending request for id \(id, privacy: .public)")
            return
        }

        if let message = envelope.error?.message {
            pendingRequest.completion(.failure(MLDaemonError.remoteError(message)))
            return
        }

        guard let result = envelope.result, !result.isNull else {
            pendingRequest.completion(.failure(MLDaemonError.invalidResponse("Missing result")))
            return
        }

        do {
            let resultData = try JSONEncoder().encode(result)
            // A successful reply proves the daemon is healthy: clear the
            // crash-loop counter so transient restarts don't accumulate
            // toward the limit (audit #8).
            if restartAttempts != 0 {
                logger.info("ml_daemon answered a request; resetting restart counter")
                restartAttempts = 0
            }
            pendingRequest.completion(.success(resultData))
        } catch {
            pendingRequest.completion(.failure(MLDaemonError.invalidResponse(error.localizedDescription)))
        }
    }

    // MARK: - Helpers

    func resolvedPython() async throws -> URL {
        if let pythonExecutable { return pythonExecutable }
        let url = try await UvBootstrap.ensureVenv(userPython: nil)
        pythonExecutable = url
        return url
    }

    func resolvedScript() throws -> URL {
        if let scriptLocation { return scriptLocation }
        if let bundled = ResourceLocator.pythonScriptURL(named: "ml_daemon") {
            scriptLocation = bundled
            return bundled
        }

        throw MLDaemonError.scriptNotFound
    }
}

internal extension MLDaemonManager {
    func setTestResponder(_ responder: ((MLRPCMethod, JSONValue) throws -> JSONValue)?) {
        testResponder = responder
    }

    /// Allows tests to bypass the default Python resolution and bundled script lookup.
    func setTestOverrides(python: URL?, script: URL?) async {
        pythonExecutable = python
        scriptLocation = script
    }

    /// Resets state for isolation between tests, ensuring processes are terminated and overrides cleared.
    func resetForTesting() async {
        await shutdown()
        pythonExecutable = nil
        scriptLocation = nil
        restartAttempts = 0
        isShuttingDown = false
        isStarting = false
        testResponder = nil
    }

    /// Inserts a pending request directly so tests can drive `handle(line:)`
    /// and `completeAllPending(with:)` without a live subprocess.
    func injectPending(id: Int, completion: @escaping (Result<Data, Error>) -> Void) {
        pending[id] = PendingRequest(
            completion: completion,
            deadline: Date().addingTimeInterval(60)
        )
    }

    /// Number of currently pending requests — test introspection only.
    func pendingCountForTesting() -> Int { pending.count }

    /// Whether a process handle is currently running — test introspection only.
    func isProcessRunningForTesting() -> Bool { process?.isRunning ?? false }

    /// Drives `restartAttempts` to the configured maximum for tests that need
    /// to exercise the restart-limit guard paths.
    func bumpRestartAttemptsToLimitForTesting() { restartAttempts = maxRestartAttempts }

    /// Current restart-attempt count — test introspection only.
    func restartAttemptsForTesting() -> Int { restartAttempts }

    /// Sets the restart-attempt count directly — test setup only.
    func setRestartAttemptsForTesting(_ value: Int) { restartAttempts = value }

    /// Marks the manager as shutting down so tests can exercise that guard.
    func markShuttingDownForTesting() { isShuttingDown = true }

    /// Test seam over the file-private `resolvedScript()` lookup.
    func resolvedScriptForTesting() throws -> URL { try resolvedScript() }
}
