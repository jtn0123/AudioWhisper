import Foundation
import os.log

// MARK: - Process lifecycle
//
// Daemon process spawning, restart, and teardown logic. Split out of
// `MLDaemonManager.swift` to keep that type's body within SwiftLint's
// `type_body_length` limit. All members remain actor-isolated.
internal extension MLDaemonManager {
    func ensureDaemonRunning() async throws {
        if let process, process.isRunning { return }
        guard !isShuttingDown else { throw MLDaemonError.daemonUnavailable("shutting down") }
        guard restartAttempts < maxRestartAttempts else { throw MLDaemonError.restartLimitReached }
        try await startProcess(isRestart: false)
    }

    func startProcess(isRestart: Bool) async throws {
        let python = try await resolvedPython()
        let script = try resolvedScript()

        if isRestart { restartAttempts += 1 } else { restartAttempts = 0 }
        if restartAttempts >= maxRestartAttempts { throw MLDaemonError.restartLimitReached }

        let proc = Process()
        proc.executableURL = python
        proc.arguments = [script.path]
        proc.environment = Self.daemonEnvironment()

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        proc.terminationHandler = { [weak self] process in
            Task { await self?.processTerminated(exitCode: process.terminationStatus) }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let message = String(bytes: data, encoding: .utf8) else { return }
            self?.logger.error("ml_daemon stderr: \(message, privacy: .public)")
        }

        do {
            try proc.run()
        } catch {
            throw MLDaemonError.daemonUnavailable("Failed to start process: \(error.localizedDescription)")
        }

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        isShuttingDown = false
        startStdoutReader(pipe: stdout)
    }

    /// Builds a minimal, allowlisted environment for the Python daemon instead
    /// of inheriting the user's entire process environment (security hardening,
    /// audit item E3). The daemon gets exactly what it needs to run Parakeet/MLX
    /// transcription and nothing more.
    ///
    /// Always-present keys: `PATH` (subprocess resolution), `HOME` (HuggingFace
    /// cache root `~/.cache/huggingface`), and `PYTHONUNBUFFERED` (line-buffered
    /// stdout so JSON-RPC responses flush immediately).
    ///
    /// Pass-through-if-set keys: locale (`LANG`/`LC_ALL` — Python text codec),
    /// `TMPDIR` (macOS per-user temp many ML libs use), `AUDIOWHISPER_APP_SUPPORT_DIR`
    /// (test/override path resolution shared with `UvBootstrap`), virtualenv vars
    /// (`VIRTUAL_ENV`, `PYTHONPATH` — keep tooling consistent even though the venv
    /// python is invoked directly), `uv` vars (`UV_CACHE_DIR`, `UV_PYTHON`), and
    /// HuggingFace cache overrides (`HF_HOME`, `HF_HUB_CACHE`, `HUGGINGFACE_HUB_CACHE`,
    /// `XDG_CACHE_HOME`) so the daemon finds models the user already downloaded.
    static func daemonEnvironment() -> [String: String] {
        let parent = ProcessInfo.processInfo.environment

        var env: [String: String] = [
            "PATH": parent["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": parent["HOME"] ?? NSHomeDirectory(),
            "PYTHONUNBUFFERED": "1"
        ]

        let passThroughIfSet = [
            "LANG", "LC_ALL", "LC_CTYPE", "TMPDIR",
            "AUDIOWHISPER_APP_SUPPORT_DIR",
            "VIRTUAL_ENV", "PYTHONPATH",
            "UV_CACHE_DIR", "UV_PYTHON",
            "HF_HOME", "HF_HUB_CACHE", "HUGGINGFACE_HUB_CACHE", "XDG_CACHE_HOME"
        ]
        for key in passThroughIfSet {
            if let value = parent[key], !value.isEmpty {
                env[key] = value
            }
        }
        return env
    }

    func startStdoutReader(pipe: Pipe) {
        stdoutReaderTask?.cancel()
        let handle = pipe.fileHandleForReading
        stdoutReaderTask = Task { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    guard !line.isEmpty else { continue }
                    await self?.handle(line: line)
                }
            } catch is CancellationError {
                return
            } catch {
                await self?.handleStdoutReaderError(error)
            }
        }
    }

    func processTerminated(exitCode: Int32) async {
        logger.error("ml_daemon exited with code \(exitCode)")
        closePipes()

        if isShuttingDown {
            process = nil
            return
        }

        completeAllPending(with: MLDaemonError.daemonUnavailable("exited (\(exitCode))"))
        process = nil

        guard restartAttempts < maxRestartAttempts else {
            // Complete any pending requests that arrived after the initial completeAllPending
            completeAllPending(with: MLDaemonError.daemonUnavailable("max restarts exceeded"))
            return
        }

        do {
            try await startProcess(isRestart: true)
        } catch {
            logger.error("Failed to restart ml_daemon: \(error.localizedDescription)")
            completeAllPending(with: error)
        }
    }

    func closePipes() {
        stdoutReaderTask?.cancel()
        stdoutReaderTask = nil

        // Close file handles BEFORE setting readabilityHandler to nil
        // This ensures no new callbacks are queued during cleanup
        stdinPipe?.fileHandleForWriting.closeFile()
        stdoutPipe?.fileHandleForReading.closeFile()
        stderrPipe?.fileHandleForReading.closeFile()

        // Now safe to clear handlers - no more data can arrive
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    func shutdown() async {
        isShuttingDown = true

        // Cancel the stdout reader task and await its completion BEFORE we
        // terminate the process or tear down pipes. This guarantees no
        // straggler `handle(line:)` calls land on a disposed pipe and avoids
        // leaking the reader Task across teardown.
        let reader = stdoutReaderTask
        stdoutReaderTask = nil
        reader?.cancel()
        _ = await reader?.value

        closePipes()
        process?.terminate()
        process = nil
        completeAllPending(with: MLDaemonError.daemonUnavailable("shutdown"))
    }

    func completeAllPending(with error: Error) {
        for (_, pendingRequest) in pending {
            pendingRequest.completion(.failure(error))
        }
        pending.removeAll()
    }

    func handleStdoutReaderError(_ error: Error) {
        guard !isShuttingDown else { return }
        logger.error("ml_daemon stdout reader failed: \(error.localizedDescription)")
    }
}
