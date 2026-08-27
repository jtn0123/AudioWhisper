import Foundation
import os.log

// MARK: - Parakeet download, on-disk cache checks, integrity, and cleanup

// Split out of MLXModelManager+Downloads.swift, which had grown past 500 lines.
//
// The seam is real rather than arbitrary: the file held two concerns that share
// only the type. One is "run a download subprocess and report progress" (the
// MLX side, which stays); the other is "what is on disk, is it intact, and how
// do we remove it" — cache probing, the integrity sidecar, deletion and unused-
// model cleanup, plus the Parakeet-specific download that keys off them.
extension MLXModelManager {
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
            guard let output = String(data: data, encoding: .utf8) else { return }
            // A single read can carry several lines; the previous version parsed
            // the whole chunk as one JSON object, so two lines arriving together
            // produced nothing at all.
            for line in output.split(separator: "\n") {
                let lineStr = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                if lineStr.isEmpty { continue }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if case .complete = self.applyDownloadProgressLine(lineStr, for: repo) {
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
