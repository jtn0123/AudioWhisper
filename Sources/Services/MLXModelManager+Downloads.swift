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
    @MainActor
    private func applyDownloadProgressLine(_ lineStr: String, for repo: String) {
        if let jsonData = lineStr.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
           let message = json["message"] as? String {
            downloadProgress[repo] = message
            logger.info("Download progress for \(repo): \(message)")
            return
        }

        if lineStr.contains("Downloading") || lineStr.contains("%") || lineStr.contains("model.safetensors") {
            if let percentRange = lineStr.range(of: #"\d+%"#, options: .regularExpression) {
                downloadProgress[repo] = "Downloading: \(String(lineStr[percentRange]))"
            } else if lineStr.contains("MB/s") || lineStr.contains("GB/s") {
                if let fileName = lineStr.split(separator: ":").first {
                    downloadProgress[repo] = "Downloading: \(fileName)..."
                }
            } else {
                downloadProgress[repo] = "Downloading model files..."
            }
            return
        }

        if lineStr.contains(".json") || lineStr.contains(".safetensors") {
            if let fileName = lineStr.split(separator: ":").first {
                downloadProgress[repo] = "Fetching: \(fileName)"
            }
        }
    }

    /// Classifies stderr output as a real error vs. progress noise.
    private nonisolated func handleDownloadStderr(_ error: String, for repo: String) {
        let lowerError = error.lowercased()
        let isRealError = (lowerError.contains("error") ||
                          lowerError.contains("exception") ||
                          lowerError.contains("failed") ||
                          lowerError.contains("traceback") ||
                          lowerError.contains("no module") ||
                          lowerError.contains("not found")) &&
                         !lowerError.contains("process exited with status: 0")

        let isProgress = error.contains("Fetching") ||
                       error.contains("Downloading") ||
                       error.contains("%") ||
                       error.contains("it/s") ||
                       error.contains("MB/s") ||
                       error.contains("GB/s")

        if isRealError && !isProgress {
            logger.error("Python stderr: \(error)")
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let errorLines = error.split(separator: "\n").prefix(2).joined(separator: " ")
                self.downloadProgress[repo] = "Error: \(errorLines)"
            }
        } else if isProgress {
            logger.info("Python progress (stderr): \(error)")
        }
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

                // Clear readability handlers to prevent file descriptor leak
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let exitStatus = process.terminationStatus

                await MainActor.run { [weak self] in
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

                // Clear readability handlers to prevent file descriptor leak
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let exitStatus = process.terminationStatus

                await MainActor.run { [weak self] in
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
