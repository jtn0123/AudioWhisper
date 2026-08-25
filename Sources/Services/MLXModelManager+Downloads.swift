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
    @MainActor
    private func applyDownloadProgressLine(_ lineStr: String, for repo: String) {
        let event = MLXDownloadEvent.parse(line: lineStr)

        if case .unstructured(let raw) = event {
            if !raw.isEmpty { logger.debug("Download stdout (unstructured) for \(repo): \(raw)") }
            return
        }

        if let text = event.displayText {
            downloadProgress[repo] = text
            logger.info("Download progress for \(repo): \(text)")
        }
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
    private func makeDownloadProcess(pythonPath: String, script: String, repo: String) -> Process {
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

    func ensureParakeetModel() async {
        // First check filesystem directly to avoid race conditions with refreshModelList
        let repo = Self.parakeetRepo
        if isModelCachedOnDisk(repo: repo) {
            logger.info("Parakeet model already cached on disk: \(repo)")
            // Update in-memory state if needed
            if !downloadedModels.contains(repo) {
                await refreshModelList()
            }
            return
        }

        // Fallback to in-memory check after refresh
        await refreshModelList()
        if downloadedModels.contains(repo) { return }
        await downloadParakeetModel()
    }

    /// Direct filesystem check for model cache - avoids race conditions with async refreshModelList
    nonisolated func isModelCachedOnDisk(repo: String) -> Bool {
        guard let refsMain = integrityFileURL(for: repo) else { return false }
        let cacheDir = refsMain.deletingLastPathComponent().deletingLastPathComponent()

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cacheDir.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        // Check for refs/main to confirm download completed. The file holds a
        // Hugging Face commit hash; require it to be pure hex.
        let rawRev = try? String(contentsOf: refsMain, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rev = rawRev, !rev.isEmpty,
              rev.allSatisfy({ $0.isHexDigit }) else {
            return false
        }

        // Resolve the snapshot directory by matching `rev` against the actual
        // directory listing rather than interpolating it into a path. `snap`
        // is therefore built only from a name returned by the filesystem.
        let snapshotsDir = cacheDir.appendingPathComponent("snapshots")
        let snapshotEntries = (try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path)) ?? []
        guard let matchedSnapshot = snapshotEntries.first(where: { $0 == rev }) else {
            return false
        }
        let snap = snapshotsDir.appendingPathComponent(matchedSnapshot)
        guard FileManager.default.fileExists(atPath: snap.path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }

        // Best-effort integrity verification. TOFU on first hit; failures
        // are logged at the call site that triggers a re-download.
        do {
            try ModelIntegrity.verify(at: refsMain, modelIdentifier: repo)
            return true
        } catch {
            logger.error(
                "Integrity check failed for cached model \(repo): \(error.localizedDescription)"
            )
            return false
        }
    }

    /// Representative file used for integrity hashing. We hash `refs/main`:
    /// it's small (a single revision hash), present after every successful
    /// `snapshot_download`, and changes whenever the cached revision changes.
    /// Hashing a full snapshot directory of multi-GB weights would block the
    /// UI for seconds on each cache check.
    nonisolated func integrityFileURL(for repo: String) -> URL? {
        let escaped = repo.replacingOccurrences(of: "/", with: "--")
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(escaped)")
        return cacheDir.appendingPathComponent("refs/main")
    }

    /// Records a fresh integrity sidecar after a successful download.
    /// Silently no-ops if the file doesn't exist — we don't want a missing
    /// sidecar to block the user from using a freshly downloaded model.
    nonisolated func recordIntegrity(for repo: String) {
        guard let refsMain = integrityFileURL(for: repo),
              FileManager.default.fileExists(atPath: refsMain.path) else { return }
        do {
            try ModelIntegrity.record(at: refsMain)
        } catch {
            logger.error("Failed to record integrity for \(repo): \(error.localizedDescription)")
        }
    }

    func downloadParakeetModel() async {
        let repo = Self.parakeetRepo
        do {
            try await downloadSerializer.run(key: repo) { [weak self] in
                await self?.performDownloadParakeetModel(repo: repo)
            }
        } catch {
            self.logger.error("Parakeet serializer failed for \(repo): \(error.localizedDescription)")
        }
    }

    private func performDownloadParakeetModel(repo: String) async {
        logger.info("Starting Parakeet model download for: \(repo)")

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

        await MainActor.run {
            isDownloading[repo] = true
            downloadProgress[repo] = "Downloading Parakeet model..."
        }

        let process = makeDownloadProcess(pythonPath: pythonPath, script: Self.parakeetScript, repo: repo)
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let line = String(data: data, encoding: .utf8),
               let jsonData = line.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
               let message = json["message"],
               let status = json["status"] {
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.downloadProgress[repo] = message
                    if status == "complete" {
                        self.downloadedModels.insert(repo)
                    }
                }
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self = self else { return }
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if let err = String(data: data, encoding: .utf8) {
                self.logger.error("Parakeet download stderr: \(err)")
            }
        }

        launchParakeetProcess(process, repo: repo, outputPipe: outputPipe, errorPipe: errorPipe)
    }

    private func launchParakeetProcess(
        _ process: Process,
        repo: String,
        outputPipe: Pipe,
        errorPipe: Pipe
    ) {
        do {
            try process.run()

            // Wait for process in background to avoid blocking main thread
            Task.detached { [outputPipe, errorPipe] in
                process.waitUntilExit()

                let exitStatus = process.terminationStatus

                await MainActor.run { [weak self] in
                    // L4: stop listening before declaring completion so a late
                    // stdout callback can't overwrite the cleared progress
                    // string with stale "Downloading…" text.
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
                        self?.logger.info("Successfully downloaded Parakeet model: \(repo)")
                    } else {
                        self?.logger.error(
                            "Failed to download Parakeet model: \(repo) with exit code: \(exitStatus)"
                        )
                    }
                }
            }
        } catch {
            // M9: clean up pipes opened above before bailing out so that a
            // failed spawn doesn't leak file descriptors and readability
            // handlers.
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            try? outputPipe.fileHandleForReading.close()
            try? errorPipe.fileHandleForReading.close()
            logger.error("Failed to launch Python process for Parakeet: \(error)")
            Task { @MainActor [weak self] in
                self?.isDownloading[repo] = false
                self?.downloadProgress[repo] = "Error: \(error.localizedDescription)"
            }
        }
    }

    /// Static Python source for the Parakeet model download. The repo name is
    /// read from `sys.argv[1]` — never interpolated into the source.
    private static let parakeetScript = """
        import json, sys, traceback, os

        # Allow downloads; avoid implicit token usage
        os.environ['HF_HUB_DISABLE_IMPLICIT_TOKEN'] = '1'
        os.environ.setdefault('HF_HUB_DISABLE_PROGRESS_BARS', '0')

        if len(sys.argv) < 2:
            print(json.dumps({"status": "error", "message": "Missing repo argument"}), flush=True)
            sys.exit(2)
        repo = sys.argv[1]

        try:
            from parakeet_mlx import from_pretrained
            # Trigger download if not cached; load from cache otherwise
            from_pretrained(repo)
            print(json.dumps({"status": "complete", "message": "Model ready"}), flush=True)
        except Exception as e:
            print(json.dumps({"status": "error", "message": str(e)}), flush=True)
            sys.exit(1)
        """

    func deleteModel(_ repo: String) async {
        // L2: validate the repo string before treating it as a path component.
        // HuggingFace repo names are "org/name" using alphanumerics, dot, dash,
        // and underscore — reject anything else to prevent path traversal,
        // null bytes, control chars, etc.
        guard Self.isValidRepoIdentifier(repo) else {
            logger.warning("deleteModel rejected invalid repo identifier: \(repo, privacy: .public)")
            return
        }
        let escapedRepo = repo.replacingOccurrences(of: "/", with: "--")
        let modelPath = cacheDirectory.appendingPathComponent("models--\(escapedRepo)")

        do {
            try FileManager.default.removeItem(at: modelPath)
            await MainActor.run {
                downloadedModels.remove(repo)
                modelSizes.removeValue(forKey: repo)
            }
            await refreshModelList()
            logger.info("Deleted model: \(repo)")
        } catch {
            logger.error("Failed to delete model: \(error.localizedDescription)")
        }
    }

    /// Validates a HuggingFace-style repo identifier (`org/name`). Rejects empty
    /// strings, leading slashes, `..` traversal segments, null bytes, control
    /// characters, and anything outside `[A-Za-z0-9_.-]/[A-Za-z0-9_.-]`.
    static func isValidRepoIdentifier(_ repo: String) -> Bool {
        guard !repo.isEmpty else { return false }
        if repo.hasPrefix("/") { return false }
        if repo.contains("..") { return false }
        if repo.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 0x20) }) {
            return false
        }
        // Exactly one '/' separating org and name.
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        return parts.allSatisfy { segment in
            segment.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }

    /// Delete all models not in the recommended list
    func cleanupUnusedModels() async {
        let recommendedRepos = Set(Self.recommendedModels.map { $0.repo })
        let modelsToDelete = downloadedModels.filter { !recommendedRepos.contains($0) }

        for repo in modelsToDelete {
            await deleteModel(repo)
        }

        logger.info("Cleaned up \(modelsToDelete.count) unused models")
    }

    /// Count of models that are downloaded but not in recommended list
    var unusedModelCount: Int {
        let recommendedRepos = Set(Self.recommendedModels.map { $0.repo })
        return downloadedModels.filter { !recommendedRepos.contains($0) }.count
    }
}
