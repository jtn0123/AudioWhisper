import Foundation
import os.log

/// Outcome of running a model-verification script.
internal struct ModelVerificationResult: Equatable {
    let succeeded: Bool
    /// Text to show the user. Already includes the "Verification failed: "
    /// prefix on failure.
    let message: String
}

/// Collects the last useful message from a verification subprocess's streams.
///
/// Pure and synchronous so parsing and success/failure wording can be tested
/// independently of subprocess execution.
internal struct VerificationOutputCollector {
    private(set) var lastStdoutMessage = ""
    private(set) var lastStderrMessage = ""

    /// Consumes a chunk of stdout. Only well-formed JSON objects carrying a
    /// `message` update the displayed text; a progress bar or a bare log line
    /// is ignored rather than guessed at.
    mutating func ingestStdout(_ chunk: String) {
        for line in chunk.split(separator: "\n").map(String.init) {
            guard let object = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                  let message = object["message"]?.stringValue else { continue }
            lastStdoutMessage = message
        }
    }

    /// Consumes a chunk of stderr. Kept only as a fallback for the failure
    /// message; it never decides success.
    mutating func ingestStderr(_ chunk: String) {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastStderrMessage = trimmed
    }

    /// Turns an exit status plus the collected output into what the user sees.
    ///
    /// Success is decided by the exit code alone. stdout supplies the wording
    /// when it has any, stderr is the fallback on failure, and there is always
    /// a concrete final message — never the in-progress "Checking model…" text
    /// left stranded.
    func result(terminationStatus: Int32, successFallback: String) -> ModelVerificationResult {
        guard terminationStatus == 0 else {
            let detail = lastStdoutMessage.isEmpty ? lastStderrMessage : lastStdoutMessage
            return ModelVerificationResult(
                succeeded: false,
                message: detail.isEmpty ? "Verification failed" : "Verification failed: \(detail)"
            )
        }
        return ModelVerificationResult(
            succeeded: true,
            message: lastStdoutMessage.isEmpty ? successFallback : lastStdoutMessage
        )
    }
}

internal enum ModelVerificationError: LocalizedError {
    case scriptNotFound(String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound(let name):
            return "Script not found: \(name)"
        }
    }
}

/// Runs a bundled Python verification script and reports the outcome.
///
/// Audit item C4. This flow existed **twice**, verbatim, inside SwiftUI view
/// files: `DashboardProviders+Parakeet.verifyParakeetModel()` and
/// `DashboardCorrection+Verify.verifyMLXModel()`. Both bootstrapped the venv,
/// built a `Process`, wired two `Pipe` readability handlers, parsed JSON from
/// stdout, ran a 180-second timeout task, cleared the handlers, and mapped the
/// exit status to a message — differing only in the script name and the success
/// wording. Each file even declared its own `private actor
/// VerificationMessageStore` with identical members.
///
/// None of it was reachable from a test, because it lived on a `View`: those two
/// files measured 0.0% and 9.5% coverage. Process launching, argument
/// construction and output parsing are ordinary service logic that happened to
/// be typed inside a view.
internal enum ModelVerificationService {
    private static let logger = Logger(
        subsystem: "com.audiowhisper.app",
        category: "ModelVerification"
    )

    /// Default ceiling on a verification run. A cold verify can legitimately
    /// take minutes; beyond this the process is terminated so the UI cannot
    /// spin forever.
    static let defaultTimeout: Duration = .seconds(180)

    /// Runs `scriptName` (a bundled `.py`) with `arguments` under `pythonPath`.
    ///
    /// - Throws: `ModelVerificationError.scriptNotFound` when the script is not
    ///   in the bundle, or whatever `Process.run()` throws.
    static func verify(
        scriptName: String,
        arguments: [String],
        pythonPath: String,
        successFallback: String,
        timeout: Duration = defaultTimeout
    ) async throws -> ModelVerificationResult {
        guard let scriptURL = ResourceLocator.pythonScriptURL(named: scriptName) else {
            throw ModelVerificationError.scriptNotFound(scriptName)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        // Arguments are passed as argv entries, never interpolated into a shell
        // or into Python source, so a hostile repo name cannot break out.
        process.arguments = [scriptURL.path] + arguments
        process.environment = MLDaemonManager.daemonEnvironment()

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        var stdoutTask: Task<Data, Never>?
        var stderrTask: Task<Data, Never>?
        var timeoutTask: Task<Void, Error>?
        defer {
            timeoutTask?.cancel()
            process.terminationHandler = nil
            try? out.fileHandleForReading.close()
            try? err.fileHandleForReading.close()
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
        }

        let exitStatus: Int32 = try await withCheckedThrowingContinuation { continuation in
            // Register before launch so even an immediate exit is observed.
            // Foundation's cross-thread waitUntilExit can remain blocked after
            // a fast child exits; the termination handler avoids that wait.
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()

                // The child owns its duplicated write descriptors after launch.
                // Release the parent's copies so the readers can reach EOF.
                try? out.fileHandleForWriting.close()
                try? err.fileHandleForWriting.close()

                // Drain concurrently while the child runs so full pipes cannot
                // deadlock it. Decode complete output after exit and stream EOF.
                stdoutTask = Task.detached { out.fileHandleForReading.readDataToEndOfFile() }
                stderrTask = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }

                timeoutTask = Task {
                    try await Task.sleep(for: timeout)
                    if process.isRunning {
                        logger.error("Verification of \(scriptName) timed out; terminating")
                        process.terminate()
                    }
                }
            } catch {
                // A process that never launched cannot deliver termination.
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        timeoutTask?.cancel()

        let stdoutData = await stdoutTask?.value ?? Data()
        let stderrData = await stderrTask?.value ?? Data()
        var collector = VerificationOutputCollector()
        if let stdout = String(data: stdoutData, encoding: .utf8) {
            collector.ingestStdout(stdout)
        }
        if let stderr = String(data: stderrData, encoding: .utf8) {
            collector.ingestStderr(stderr)
        }

        return collector.result(
            terminationStatus: exitStatus,
            successFallback: successFallback
        )
    }
}
