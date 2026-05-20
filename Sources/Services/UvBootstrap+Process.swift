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

    @discardableResult
    static func runInDir(_ cmd: String, _ args: [String], cwd: URL) -> ProcessResult {
        let process = Process()
        process.currentDirectoryURL = cwd
        process.executableURL = URL(fileURLWithPath: cmd)
        process.arguments = args
        return runProcess(process)
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

/// Reads a `FileHandle` to EOF on a background queue; `value` blocks until done.
/// Used by `runProcess` (H8) so stdout and stderr are drained in parallel with
/// process execution rather than after `waitUntilExit`.
private final class PipeReader {
    private let group = DispatchGroup()
    private var data = Data()
    init(handle: FileHandle) {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let buffer = handle.readDataToEndOfFile()
            self?.data = buffer
            self?.group.leave()
        }
    }
    var value: Data {
        group.wait()
        return data
    }
}
