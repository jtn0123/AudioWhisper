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
/// Pure and synchronous so it is testable without spawning anything — the part
/// of verification that can actually be wrong is the parsing and the
/// success/failure wording, not the `Process` plumbing.
internal struct VerificationOutputCollector {
    private(set) var lastStdoutMessage = ""
    private(set) var lastStderrMessage = ""

    /// Consumes a chunk of stdout. Only well-formed JSON objects carrying a
    /// `message` update the displayed text; a progress bar or a bare log line
    /// is ignored rather than guessed at.
    mutating func ingestStdout(_ chunk: String) {
        for line in chunk.split(separator: "\n").map(String.init) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["message"] as? String else { continue }
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

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let collector = CollectorBox()
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            collector.ingestStdout(text)
        }
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            collector.ingestStderr(text)
        }

        defer {
            // Clear before returning so a late callback cannot fire against a
            // finished run, and so the handles do not leak.
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
        }

        try process.run()

        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            if process.isRunning {
                logger.error("Verification of \(scriptName) timed out; terminating")
                process.terminate()
            }
        }
        await Task.detached { process.waitUntilExit() }.value
        timeoutTask.cancel()

        return collector.snapshot().result(
            terminationStatus: process.terminationStatus,
            successFallback: successFallback
        )
    }

    /// Lock-guarded box so the pipe handlers — which fire on arbitrary queues —
    /// can feed the collector without data races. Replaces the two private
    /// `actor VerificationMessageStore` copies, whose `Task { await … }` hops
    /// meant a late chunk could land after the result had already been read.
    private final class CollectorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var collector = VerificationOutputCollector()

        func ingestStdout(_ text: String) {
            lock.lock(); defer { lock.unlock() }
            collector.ingestStdout(text)
        }

        func ingestStderr(_ text: String) {
            lock.lock(); defer { lock.unlock() }
            collector.ingestStderr(text)
        }

        func snapshot() -> VerificationOutputCollector {
            lock.lock(); defer { lock.unlock() }
            return collector
        }
    }
}
