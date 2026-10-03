import Foundation
import os.log

// MARK: - Model Downloads & Integrity

extension MLXModelManager {
    func downloadModel(_ repo: String) async {
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
        logger.info("Starting MLX model download for: \(repo)")
        // Ensure managed Python via uv
        let pythonPath: String
        do {
            let resolvedPython = try await UvBootstrap.ensureVenv(userPython: nil) { msg in
                self.logger.info("uv: \(msg)")
            }
            pythonPath = resolvedPython.path
        } catch {
            logger.error("Failed to prepare Python environment: \(error.localizedDescription)")
            await MainActor.run {
                downloadProgress[repo] = "Error: Could not prepare Python environment"
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

        let process = makeDownloadProcess(pythonPath: pythonPath, script: Self.downloadScript, repo: repo)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let output = String(data: data, encoding: .utf8) else { return }
            self.logger.info("Python stdout: \(output)")
            // Process each line separately as JSON might come in multiple lines
            for line in output.split(separator: "\n") {
                let lineStr = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if lineStr.isEmpty { continue }
                Task { @MainActor [weak self] in
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

        launchDownloadProcess(process, repo: repo, outputPipe: outputPipe, errorPipe: errorPipe)
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
    /// in `launchDownloadProcess`. Both are contracts we own. stderr is
    /// `huggingface_hub`'s own output, whose format we do not control, so it is
    /// logged and nothing more.
    private nonisolated func handleDownloadStderr(_ error: String, for repo: String) {
        let trimmed = error.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logger.info("Python stderr for \(repo): \(trimmed)")
    }

    /// Builds a configured Python process for a download script.
    ///
    /// `repo` is passed as a command-line argument (`sys.argv[1]`) rather than
    /// interpolated into the Python source, so a hostile repo name cannot break
    /// out of a string literal and execute arbitrary code (audit item: command
    /// injection via model repo names).
    ///
    /// The environment is a minimal allowlist (see `daemonEnvironment()`) rather
    /// than the full inherited process environment, so HuggingFace tokens, proxy
    /// credentials, etc. are not leaked into the download subprocess.
    /// Not `private`: the Parakeet download in `MLXModelManager+Cache.swift`
    /// builds its process the same way, and `private` is file-scoped.
    func makeDownloadProcess(pythonPath: String, script: String, repo: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", script, repo]
        process.environment = MLDaemonManager.daemonEnvironment()
        return process
    }

    /// Launches a download process and handles completion/cleanup off the main thread.
    private func launchDownloadProcess(
        _ process: Process,
        repo: String,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) {
        do {
            logger.info("Launching Python process...")
            try process.run()
            logger.info("Python process launched, waiting for completion...")

            Task.detached { [outputPipe, errorPipe] in
                process.waitUntilExit()

                let exitStatus = process.terminationStatus

                await MainActor.run { [weak self] in
                    // L4: stop listening for stdout/stderr BEFORE we declare
                    // completion. Clearing handlers after `removeValue` allowed
                    // a late callback to overwrite the cleared progress string
                    // with stale "Downloading…" text.
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    self?.isDownloading[repo] = false
                    if exitStatus != 0 {
                        self?.downloadProgress[repo] = "Error: Download failed (exit code: \(exitStatus))"
                    } else {
                        self?.downloadProgress.removeValue(forKey: repo)
                    }

                    if exitStatus == 0 {
                        self?.recordIntegrity(for: repo)
                        Task {
                            await self?.refreshModelList()
                        }
                        self?.logger.info("Successfully downloaded model: \(repo)")
                    } else {
                        self?.logger.error(
                            "Failed to download model: \(repo) with exit code: \(exitStatus)"
                        )
                    }
                }
            }
        } catch {
            // M9: pipes opened above leak (file descriptors + readability
            // handlers) if `process.run()` throws. Clear and close them
            // before bailing out.
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            logger.error("Failed to launch Python process: \(error)")
            Task { @MainActor [weak self] in
                self?.isDownloading[repo] = false
                self?.downloadProgress[repo] = "Error: \(error.localizedDescription)"
            }
        }
    }

    /// Static Python source for the HuggingFace model download. The repo name is
    /// read from `sys.argv[1]` — never interpolated into the source — so a
    /// malicious repo string cannot escape a string literal and run code.
    private static let downloadScript = """
        import sys
        import json
        import os

        # Show progress
        os.environ.setdefault('HF_HUB_DISABLE_PROGRESS_BARS', '0')
        os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN'] = '1'

        if len(sys.argv) < 2:
            print(json.dumps({"status": "error", "message": "Missing repo argument"}), flush=True)
            sys.exit(2)
        repo = sys.argv[1]

        try:
            print(json.dumps({"status": "downloading", "message": "Downloading model files..."}), flush=True)
            from huggingface_hub import snapshot_download

            # Download files only - don't load into memory
            path = snapshot_download(repo)
            print(json.dumps({"status": "complete", "message": "Download complete"}), flush=True)

        except ImportError as e:
            print(json.dumps({"status": "error", "message": f"huggingface_hub not installed: {e}"}), flush=True)
            sys.exit(1)
        except Exception as e:
            print(json.dumps({"status": "error", "message": str(e)}), flush=True)
            sys.exit(1)
        """
}
