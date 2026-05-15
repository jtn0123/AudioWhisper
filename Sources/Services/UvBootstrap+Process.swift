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
        process.waitUntilExit()
        // Read output before closing handles
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        // Explicitly close file handles to ensure immediate resource cleanup
        try? outPipe.fileHandleForReading.close()
        try? errPipe.fileHandleForReading.close()
        let stdout = String(data: outData, encoding: .utf8) ?? ""
        let stderr = String(data: errData, encoding: .utf8) ?? ""
        return ProcessResult(stdout: stdout, stderr: stderr, status: process.terminationStatus)
    }
}
