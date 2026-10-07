import Foundation
import Darwin
import os.log

// MARK: - Model Downloads & Integrity

extension MLXModelManager {
    func downloadModel(_ repo: String) async {
        guard !Task.isCancelled else {
            downloadProgress[repo] = "Cancelled. Partial files are kept for retry."
            return
        }
        // Serialize per-repo: if another caller is already downloading the
        // same repo, await that task instead of starting a duplicate one.
        // The body never throws — the serializer's error channel is unused
        // here, but we keep the call site simple by tolerating it.
        do {
            try await downloadSerializer.run(key: repo) { [weak self] in
                await self?.performDownloadModel(repo)
            }
        } catch {
            self.logger.error("Download serializer failed for \(repo): \(error.localizedDescription)")
        }
    }

    private func performDownloadModel(_ repo: String) async {
        guard !Task.isCancelled else {
            downloadProgress[repo] = "Cancelled. Partial files are kept for retry."
            return
        }
        logger.info("Starting MLX model download for: \(repo)")
        cancelledDownloads.remove(repo)
        downloadFraction.removeValue(forKey: repo)
        isDownloading[repo] = true
        downloadProgress[repo] = "Preparing local Python runtime…"
        defer { isDownloading[repo] = false }
        // Ensure managed Python via uv
        let pythonPath: String
        do {
            let resolvedPython = try await prepareDownloadPython()
            try Task.checkCancellation()
            pythonPath = resolvedPython.path
        } catch {
            logger.error("Failed to prepare Python environment: \(error.localizedDescription)")
            await MainActor.run {
                downloadProgress[repo] = Task.isCancelled ? "Cancelled. Partial files are kept for retry."
                    : "Error: \(error.localizedDescription)"
                isDownloading[repo] = false
            }
            return
        }
        logger.info("Using managed Python at: \(pythonPath.redactingHomeDirectory)")

        await MainActor.run {
            isDownloading[repo] = true
            downloadProgress[repo] = "Checking Python environment..."
        }

        logger.info(
            "Starting download for model: \(repo) with Python: \(pythonPath.redactingHomeDirectory)"
        )

        guard let process = makeDownloadProcess(pythonPath: pythonPath, repo: repo) else {
            await reportMissingDownloadScript(for: repo)
            return
        }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        let progressBuffer = DownloadOutputBuffer()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in progressBuffer.append(data) {
                let lineStr = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if lineStr.isEmpty { continue }
                Task { @MainActor [weak self] in
                    guard process.isRunning else { return }
                    self?.applyDownloadProgressLine(lineStr, for: repo)
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let errorOutput = String(data: data, encoding: .utf8) else { return }
            self.handleDownloadStderr(errorOutput, for: repo)
        }

        await runDownloadProcess(
            process, repo: repo, outputPipe: outputPipe, errorPipe: errorPipe, progressBuffer: progressBuffer)
    }

    /// Parses one stdout line from the download script and updates UI progress.
    ///
    /// Audit item B2: the substring fallbacks that used to live here (scanning
    /// for `"Downloading"`, `"%"`, `"MB/s"`, `".safetensors"` …) are gone. They
    /// guessed at `huggingface_hub`'s progress-bar format, which is not a
    /// stable contract, and in practice never fired — HF writes its bars to
    /// stderr, not stdout. Structured JSON is now the only thing that moves the
    /// UI; anything else is logged and ignored.
    /// `internal`, not `private`, because the Parakeet download in
    /// `MLXModelManager+Cache` parses the same line format. It used to do so
    /// with its own `JSONSerialization ... as? [String: String]` cast, which is
    /// how the B2 fix ended up applied to one of the two download paths and not
    /// the other: the Parakeet copy required BOTH `status` and `message` to be
    /// strings or it dropped the line entirely, and had no `error` branch at
    /// all. Swift `private` is file-scoped, so sharing this is the fix.
    ///
    /// Returns the parsed event so a caller can act on it further — the
    /// Parakeet path also marks the model present on `.complete`.
    @MainActor
    @discardableResult
    func applyDownloadProgressLine(_ lineStr: String, for repo: String) -> MLXDownloadEvent {
        let event = MLXDownloadEvent.parse(line: lineStr)

        if case .unstructured(let raw) = event {
            if !raw.isEmpty { logger.debug("Download stdout (unstructured) for \(repo): \(raw)") }
            return event
        }

        if let text = event.displayText {
            downloadProgress[repo] = text
            logger.info("Download progress for \(repo): \(text)")
        }
        if let fraction = event.fraction { downloadFraction[repo] = fraction }
        return event
    }

    /// Records stderr for diagnostics. Deliberately does not classify it.
    ///
    /// Audit item B2. This used to decide error-vs-progress by substring —
    /// `"error"`, `"traceback"`, `"no module"` meant failure; `"Fetching"`,
    /// `"%"`, `"MB/s"` meant progress — and on a "real error" it wrote
    /// `downloadProgress[repo] = "Error: …"`. Two ways that misfires: an
    /// ordinary `huggingface_hub` progress bar containing the word "error"
    /// (a repo or filename can) surfaced as a failure, and a genuine failure
    /// whose text happened to contain "%" was silently swallowed as progress,
    /// leaving a spinner that never resolved.
    ///
    /// Failure is now decided where it is actually knowable: the script's
    /// `{"status": "error"}` line on stdout, and the process exit code checked
    /// in `runDownloadProcess`. Both are contracts we own. stderr is
    /// `huggingface_hub`'s own output, whose format we do not control, so it is
    /// logged and nothing more.
    private nonisolated func handleDownloadStderr(_ error: String, for repo: String) {
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logger.info("Python stderr for \(repo): \(trimmed)")
    }

    /// Builds the Python process that downloads `repo` with the bundled
    /// `download_model.py`, or nil if the script is missing from the bundle.
    ///
    /// `repo` — and its pinned revision, for a model the app ships (see
    /// `ModelPins`) — are passed as command-line arguments, never interpolated
    /// into Python source, so a hostile repo name cannot run code. The script
    /// used to be a Python string literal in this file, which also put it out
    /// of reach of `make typecheck`.
    ///
    /// The environment is a minimal allowlist (see `daemonEnvironment()`) rather
    /// than the full inherited process environment, so HuggingFace tokens, proxy
    /// credentials, etc. are not leaked into the download subprocess.
    /// Not `private`: the Parakeet download in `MLXModelManager+Cache.swift`
    /// uses it too, and `private` is file-scoped.
    func makeDownloadProcess(pythonPath: String, repo: String) -> Process? {
        if let downloadProcessFactory { return downloadProcessFactory(pythonPath, repo) }
        guard let script = ResourceLocator.pythonScriptURL(named: "download_model") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [script.path, repo] + ModelPins.scriptArguments(for: repo)
        process.environment = MLDaemonManager.daemonEnvironment()
        return process
    }

    /// Clears the busy state when `download_model.py` cannot be found — a
    /// broken bundle, not something a retry will fix.
    func reportMissingDownloadScript(for repo: String) async {
        logger.error("download_model.py is missing from the app bundle; cannot download \(repo)")
        await MainActor.run {
            downloadProgress[repo] = "Error: Download script missing from the app bundle"
            isDownloading[repo] = false
        }
    }

    /// Runs a download process to completion, then records the outcome.
    ///
    /// This used to launch the process and return at once, leaving a detached
    /// task to wait for it. Every `await downloadModel(_:)` therefore resumed
    /// while the download had barely started, which broke the two things that
    /// awaited it: `downloadSerializer` guarded only the launch, so a second
    /// request for the same repo started a second download, and the nightly
    /// end-to-end test checked the cache one second into a 2.5 GB fetch and
    /// failed every night with `modelNotReady`.
    ///
    /// Not `private`: the Parakeet download in `MLXModelManager+Cache.swift`
    /// runs through it too.
    func runDownloadProcess(
        _ process: Process, repo: String, outputPipe: Pipe, errorPipe: Pipe,
        progressBuffer: DownloadOutputBuffer? = nil
    ) async {
        guard !Task.isCancelled, !cancelledDownloads.contains(repo) else {
            isDownloading[repo] = false
            downloadProgress[repo] = "Cancelled. Partial files are kept for retry."
            return
        }
        activeDownloads[repo] = process
        defer {
            activeDownloads.removeValue(forKey: repo)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
        }
        let exitStatus: Int32
        do {
            logger.info("Launching download process for \(repo)")
            exitStatus = try await Self.runToExit(process)
        } catch {
            // M9: pipes opened by the caller leak (file descriptors + readability
            // handlers) if `process.run()` throws. Clear and close them.
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            logger.error("Failed to launch download process for \(repo): \(error)")
            isDownloading[repo] = false
            downloadProgress[repo] = "Error: \(error.localizedDescription)"
            return
        }

        // L4: stop listening for stdout/stderr BEFORE declaring completion, so a
        // late callback cannot overwrite the cleared progress string with stale
        // "Downloading…" text.
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        isDownloading[repo] = false

        if cancelledDownloads.contains(repo) || Task.isCancelled {
            downloadProgress[repo] = "Cancelled. Partial files are kept for retry."
            downloadFraction.removeValue(forKey: repo)
            return
        }

        guard exitStatus == 0 else {
            if let message = progressBuffer?.error {
                downloadProgress[repo] = "Error: \(message)"
            } else if downloadProgress[repo]?.hasPrefix("Error:") != true {
                downloadProgress[repo] = "Error: Download failed (exit code: \(exitStatus))"
            }
            logger.error("Failed to download model: \(repo) with exit code: \(exitStatus)")
            return
        }
        downloadProgress.removeValue(forKey: repo)
        downloadFraction.removeValue(forKey: repo)
        recordIntegrity(for: repo)
        await refreshModelList()
        logger.info("Successfully downloaded model: \(repo)")
    }

    func cancelDownload(_ repo: String) async {
        cancelledDownloads.insert(repo)
        downloadProgress[repo] = "Cancelling…"
        let process = activeDownloads[repo]
        if let process, process.isRunning { process.terminate() }
        let escalation = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        await downloadSerializer.cancel(key: repo)
        escalation.cancel()
    }

    /// Starts `process` and suspends until it exits, without parking a thread
    /// on `waitUntilExit()` for the length of a multi-gigabyte download.
    nonisolated static func runToExit(_ process: Process) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            // Installed before `run()`, so an instant exit cannot be missed.
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                // A process that never started never terminates, so this is the
                // only resume on this path.
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
