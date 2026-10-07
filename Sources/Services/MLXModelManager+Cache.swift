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
        await downloadParakeetModel(repo: repo)
    }

    /// Direct filesystem check for model cache - avoids race conditions with async refreshModelList
    nonisolated func isModelCachedOnDisk(repo: String) -> Bool {
        guard let refsMain = integrityFileURL(for: repo) else { return false }
        let cacheDir = refsMain.deletingLastPathComponent().deletingLastPathComponent()

        guard HuggingFaceCache.completeSnapshot(in: cacheDir) else { return false }

        // Best-effort integrity verification. TOFU on first hit; failures
        // are logged at the call site that triggers a re-download.
        do {
            try ModelIntegrity.verify(at: refsMain)
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
        let cacheDir = cacheDirectory.appendingPathComponent("models--\(escaped)")
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

    func downloadParakeetModel(repo: String? = nil) async {
        let repo = repo ?? Self.parakeetRepo
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
                downloadProgress[repo] = "Error: \(error.localizedDescription)"
                isDownloading[repo] = false
            }
            return
        }

        await MainActor.run {
            isDownloading[repo] = true
            downloadProgress[repo] = "Downloading Parakeet model..."
        }

        guard let process = makeDownloadProcess(pythonPath: pythonPath, repo: repo) else {
            await reportMissingDownloadScript(for: repo)
            return
        }
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

        await runDownloadProcess(process, repo: repo, outputPipe: outputPipe, errorPipe: errorPipe)
    }

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

    /// What "Clean up old models" deletes: cached retired correction models,
    /// except the one correction is set to use. In `retiredCorrectionModels`
    /// order.
    ///
    /// This used to be every cached model outside `recommendedModels`, which
    /// took in the Parakeet model the app transcribes with, any MLX model
    /// another app had put in the shared cache, and — for a user the default
    /// migration kept on Llama-3.2-1B — the correction model in use.
    var unusedModels: [String] {
        let selected = AppDefaults.semanticCorrectionModelRepo
        return Self.retiredCorrectionModels.filter { downloadedModels.contains($0) && $0 != selected }
    }

    var unusedModelCount: Int { unusedModels.count }

    /// Tooltip for the cleanup buttons: what a click will delete, by name.
    var cleanupHelpText: String {
        let names = unusedModels.map { $0.split(separator: "/").last.map(String.init) ?? $0 }
        return "Deletes " + names.joined(separator: ", ")
    }

    func cleanupUnusedModels() async {
        let modelsToDelete = unusedModels
        for repo in modelsToDelete {
            await deleteModel(repo)
        }
        logger.info("Cleaned up \(modelsToDelete.count) unused models")
    }
}
