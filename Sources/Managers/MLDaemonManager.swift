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
    private let requestTimeoutSeconds: UInt64 = 60

    var process: Process?
    var stdinPipe: Pipe?
    var stdoutPipe: Pipe?
    var stderrPipe: Pipe?
    var pending: [Int: PendingRequest] = [:]
    private var nextRequestID: Int = 1
    var restartAttempts: Int = 0
    var isShuttingDown = false
    var stdoutReaderTask: Task<Void, Never>?
    private var pythonExecutable: URL?
    private var scriptLocation: URL?
    private var testResponder: ((String, [String: Any]) throws -> Any)?

    // MARK: - Public API

    func transcribe(repo: String, pcmPath: String) async throws -> String {
        struct TranscribeResult: Decodable { let success: Bool; let text: String; let error: String? }
        let result: TranscribeResult = try await sendRequest(
            method: "transcribe",
            params: ["repo": repo, "pcm_path": pcmPath]
        )
        guard result.success else { throw MLDaemonError.remoteError(result.error ?? "Transcription failed") }
        return result.text
    }

    func correct(repo: String, text: String, prompt: String?) async throws -> String {
        struct CorrectionResult: Decodable { let success: Bool; let text: String; let error: String? }
        var params: [String: Any] = ["repo": repo, "text": text]
        if let prompt = prompt { params["prompt"] = prompt }
        let result: CorrectionResult = try await sendRequest(method: "correct", params: params)
        guard result.success else { throw MLDaemonError.remoteError(result.error ?? "Correction failed") }
        return result.text
    }

    func warmup(type: String, repo: String) async throws {
        struct WarmupResult: Decodable { let success: Bool? }
        _ = try await sendRequest(method: "warmup", params: ["type": type, "repo": repo]) as WarmupResult
    }

    func ping() async -> Bool {
        struct PingResult: Decodable { let pong: Bool }
        do {
            let result: PingResult = try await sendRequest(method: "ping", params: [:])
            return result.pong
        } catch {
            logger.error("Ping failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Core JSON-RPC plumbing

    private func sendRequest<Response: Decodable>(method: String, params: [String: Any]) async throws -> Response {
        if let testResponder {
            let resultObject = try testResponder(method, params)
            let data = try JSONSerialization.data(withJSONObject: resultObject, options: [])
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw MLDaemonError.invalidResponse(error.localizedDescription)
            }
        }
        // Drop any pending entries whose deadline has passed. This is cheap
        // (no separate timer) and guarantees the `pending` map can't grow
        // unboundedly if responses are lost.
        sweepExpiredRequests()
        try await ensureDaemonRunning()

        let requestID = nextRequestID
        nextRequestID += 1

        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method
        ]
        if !params.isEmpty {
            payload["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let writer = stdinPipe?.fileHandleForWriting else {
            throw MLDaemonError.daemonUnavailable("stdin unavailable")
        }

        // Write with error handling
        do {
            try writer.write(contentsOf: data)
            try writer.write(contentsOf: Data([0x0a])) // newline
        } catch {
            logger.error("Failed to write to daemon stdin: \(error.localizedDescription)")
            throw MLDaemonError.writeFailed
        }

        // Use withCheckedThrowingContinuation with timeout via Task
        let timeoutNanos = requestTimeoutSeconds * 1_000_000_000

        let deadline = Date().addingTimeInterval(TimeInterval(requestTimeoutSeconds))
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Response, Error>) in
            // Store pending request in actor context (this is synchronous within actor)
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

    private func removePendingRequest(_ id: Int) {
        pending.removeValue(forKey: id)
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
            let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            let id = json["id"] as? Int
        else {
            logger.error("Malformed JSON-RPC response")
            return
        }

        guard let pendingRequest = pending.removeValue(forKey: id) else {
            logger.error("No pending request for id \(id, privacy: .public)")
            return
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            pendingRequest.completion(.failure(MLDaemonError.remoteError(message)))
            return
        }

        guard let result = json["result"] else {
            pendingRequest.completion(.failure(MLDaemonError.invalidResponse("Missing result")))
            return
        }

        do {
            let resultData = try JSONSerialization.data(withJSONObject: result, options: [])
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
    func setTestResponder(_ responder: ((String, [String: Any]) throws -> Any)?) {
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

    /// Marks the manager as shutting down so tests can exercise that guard.
    func markShuttingDownForTesting() { isShuttingDown = true }

    /// Test seam over the file-private `resolvedScript()` lookup.
    func resolvedScriptForTesting() throws -> URL { try resolvedScript() }
}
