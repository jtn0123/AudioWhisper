import Foundation
import os.log

internal class AppSetupHelper {
    // MARK: - Semantic-correction model migration (audit item B1)

    /// One-time migration that pins existing installs to the pre-2.0 correction
    /// model so the B1 fix doesn't silently switch them.
    ///
    /// Before B1, the two correction call sites bypassed
    /// `AppDefaults.semanticCorrectionModelRepo` whenever the key was unset and
    /// hardcoded Llama-3.2-1B, while the Dashboard displayed and badged
    /// Qwen3-1.7B as RECOMMENDED. Those call sites now honour `AppDefaults`
    /// unconditionally, which makes Qwen3 the real default.
    ///
    /// For a user who never picked a model, that flip would mean their next
    /// dictation quietly downloads a different ~1 GB model. So: if there is no
    /// explicit choice AND the legacy model is already on disk, write the legacy
    /// repo explicitly. Their behaviour is unchanged and the Dashboard now tells
    /// the truth about which model is in use. Everyone else — fresh installs, and
    /// users who never downloaded the legacy model — gets the Qwen3 default.
    ///
    /// Idempotent: writing the key makes `hasValue` true on every later launch.
    static func migrateSemanticCorrectionModelDefault() {
        let hasExplicitChoice = AppDefaults.hasValue(for: .semanticCorrectionModelRepo)
        let downloadedPriorDefaults = AppDefaults.priorSemanticCorrectionModelRepos
            .filter { isModelInHuggingFaceCache($0) }

        guard let pinned = priorDefaultToPin(
            hasExplicitChoice: hasExplicitChoice,
            downloadedPriorDefaults: downloadedPriorDefaults
        ) else { return }

        AppDefaults.semanticCorrectionModelRepo = pinned
        Logger.app.info("Pinned semantic-correction model to a previously-shipped default already on disk.")
    }

    /// Pure decision half of `migrateSemanticCorrectionModelDefault`, split out
    /// so the policy is testable without touching UserDefaults or the filesystem.
    ///
    /// Returns the repo to pin, or `nil` to let the current default apply.
    /// `downloadedPriorDefaults` must preserve
    /// `AppDefaults.priorSemanticCorrectionModelRepos` order (newest first), so
    /// a user who has several old models cached keeps the most recent one.
    static func priorDefaultToPin(
        hasExplicitChoice: Bool,
        downloadedPriorDefaults: [String]
    ) -> String? {
        guard !hasExplicitChoice else { return nil }
        return downloadedPriorDefaults.first
    }

    /// Whether `repo` has a snapshot directory in the HuggingFace hub cache.
    ///
    /// Mirrors the layout `MLXModelManager` uses (`models--org--name`) rather
    /// than reading `MLXModelManager.downloadedModels`, which is populated
    /// asynchronously after launch and would race this check.
    static func isModelInHuggingFaceCache(
        _ repo: String,
        cacheDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    ) -> Bool {
        // Reject anything that isn't a plain `org/name` identifier before using
        // it as a path component (same guard as MLXModelManager.deleteModel).
        let allowed = repo.allSatisfy { $0.isLetter || $0.isNumber || "/._-".contains($0) }
        guard allowed, !repo.hasPrefix("/"), !repo.contains("..") else { return false }

        let escaped = repo.replacingOccurrences(of: "/", with: "--")
        let modelPath = cacheDirectory.appendingPathComponent("models--\(escaped)")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Deletes recordings a crashed or force-quit dictation left in the
    /// temporary directory. A finished dictation removes its own audio; this
    /// catches the ones that never got the chance, so spoken audio doesn't
    /// linger on disk. Runs at launch.
    static func cleanupOldTemporaryFiles(
        in tempDirectory: URL = FileManager.default.temporaryDirectory, now: Date = Date()
    ) {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: []
            )
            let audioFiles = files.filter { $0.lastPathComponent.hasPrefix("recording_") && $0.pathExtension == "m4a" }

            let cutoffDate = now.addingTimeInterval(-24 * 60 * 60) // 24 hours ago

            for file in audioFiles {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    if let creationDate = attributes[.creationDate] as? Date, creationDate < cutoffDate {
                        try FileManager.default.removeItem(at: file)
                    }
                } catch {
                    Logger.app.error("Failed to clean up file \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            Logger.app.error("Failed to clean up temporary files: \(error.localizedDescription)")
        }
    }
}
