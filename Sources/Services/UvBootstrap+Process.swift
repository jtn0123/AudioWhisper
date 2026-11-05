import Foundation

// MARK: - Subprocess Execution

extension UvBootstrap {
    /// Captured output of a finished subprocess.
    struct ProcessResult {
        let stdout: String
        let stderr: String
        let status: Int32
    }

    @discardableResult
    static func run(_ cmd: String, _ args: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        return runProcess(process)
    }

    /// Async variant for the slow commands (`uv venv`, `uv sync`, import
    /// checks). It never blocks a Swift-concurrency thread: exit arrives via
    /// `terminationHandler` and the pipes drain on dispatch threads. A child
    /// still running at `timeout` is terminated and reported as failed.
    static func runInDir(_ cmd: String, _ args: [String], cwd: URL, timeout: Duration) async -> ProcessResult {
        let process = Process()
        process.currentDirectoryURL = cwd
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        return await runProcess(process, timeout: timeout)
    }

    private static func runProcess(_ process: Process, timeout: Duration) async -> ProcessResult {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        defer {
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
        }
        let watchdog = Task { () -> Bool in
            guard (try? await Task.sleep(for: timeout)) != nil, process.isRunning else { return false }
            process.terminate()
            return true
        }
        let launched = await launch(process, out: outPipe, err: errPipe)
        watchdog.cancel()
        switch launched {
        case .failure(let error):
            return ProcessResult(stdout: "", stderr: String(describing: error), status: 1)
        case .success(let run):
            let stdout = String(bytes: await run.out.read(), encoding: .utf8) ?? ""
            var stderr = String(bytes: await run.err.read(), encoding: .utf8) ?? ""
            if await watchdog.value { stderr += "\nTimed out after \(timeout); the process was stopped." }
            return ProcessResult(stdout: stdout, stderr: stderr, status: run.status)
        }
    }

    private struct Launched {
        let status: Int32
        let out: PipeReader
        let err: PipeReader
    }

    /// Starts `process` and suspends until it exits. Both pipes drain in
    /// parallel from the start, so a child filling one can't stall.
    private static func launch(
        _ process: Process, out: Pipe, err: Pipe
    ) async -> Result<Launched, Error> {
        let outReader = PipeReader(handle: out.fileHandleForReading)
        let errReader = PipeReader(handle: err.fileHandleForReading)
        let status: Result<Int32, Error> = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: .success($0.terminationStatus)) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                // No child holds the write ends, so closing ours lets the readers finish.
                try? out.fileHandleForWriting.close()
                try? err.fileHandleForWriting.close()
                continuation.resume(returning: .failure(error))
            }
        }
        return status.map { Launched(status: $0, out: outReader, err: errReader) }
    }

    /// Launches a configured process, captures stdout/stderr, and cleans up handles.
    private static func runProcess(_ process: Process) -> ProcessResult {
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            // Close file handles to prevent resource leak
            try? outPipe.fileHandleForReading.close()
            try? errPipe.fileHandleForReading.close()
            return ProcessResult(stdout: "", stderr: String(describing: error), status: 1)
        }
        // H8: drain stdout and stderr concurrently BEFORE `waitUntilExit`. A
        // child that writes more than the pipe capacity (64 KiB on macOS)
        // blocks on its own stdout write if we wait first, deadlocking us.
        let outRead = PipeReader(handle: outPipe.fileHandleForReading)
        let errRead = PipeReader(handle: errPipe.fileHandleForReading)
        process.waitUntilExit()
        let outData = outRead.value
        let errData = errRead.value
        // Explicitly close file handles to ensure immediate resource cleanup
        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()
        let stdout = String(bytes: outData, encoding: .utf8) ?? ""
        let stderr = String(bytes: errData, encoding: .utf8) ?? ""
        return ProcessResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}

/// Reads a `FileHandle` to EOF on a dispatch thread, so stdout and stderr
/// drain in parallel with the child (H8). `value` blocks; `read()` suspends
/// and is the one to use from async code.
final class PipeReader: @unchecked Sendable {
    private let group = DispatchGroup()
    private var buffer = Data()
    init(handle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            buffer = handle.readDataToEndOfFile()
            group.leave()
        }
    }
    var value: Data {
        group.wait()
        return buffer
    }
    func read() async -> Data {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global(qos: .userInitiated)) { [self] in continuation.resume(returning: buffer) }
        }
    }
}
