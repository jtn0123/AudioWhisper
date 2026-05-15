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
        proc.environment = ProcessInfo.processInfo.environment.merging(["PYTHONUNBUFFERED": "1"]) { _, new in new }

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
