import Foundation
import Observation
import os.log

internal struct MLXModel: Identifiable, Equatable {
    let id = UUID()
    let repo: String
    let estimatedSize: String
    let description: String
    let name: String?

    init(repo: String, estimatedSize: String, description: String, name: String? = nil) {
        self.repo = repo
        self.estimatedSize = estimatedSize
        self.description = description
        self.name = name
    }

    var displayName: String {
        name ?? repo.split(separator: "/").last.map(String.init) ?? repo
    }
}

@Observable
@MainActor
internal final class MLXModelManager {
    static let shared = MLXModelManager()

    var downloadedModels: Set<String> = []
    var modelSizes: [String: Int64] = [:]
    var isDownloading: [String: Bool] = [:]
    var downloadProgress: [String: String] = [:]
    var totalCacheSize: Int64 = 0

    let logger = Logger(subsystem: "com.audiowhisper.app", category: "MLXModelManager")
    let cacheDirectory: URL

    /// Serializes concurrent downloads of the same repo. Two callers asking for
    /// the SAME repo share one in-flight task; two callers asking for DIFFERENT
    /// repos proceed in parallel.
    let downloadSerializer = DiskMutationSerializer<String>()

    static var parakeetRepo: String {
        // Note: returns the raw stored string (not validated against `ParakeetModel`),
        // allowing future model repos that aren't yet in the enum. For validated
        // access, use `AppDefaults.selectedParakeetModel`.
        AppDefaults.defaults.string(forKey: AppDefaults.Key.selectedParakeetModel.rawValue)
            ?? ParakeetModel.v2English.rawValue
    }

    /// Curated local editors, ordered from lightweight to larger models.
    /// Qwen3.5/3.8 were compared on 64 English stress cases with thinking off
    /// on an M5 Pro / 48 GB. See `.Codex/bench/2026-10-06-qwen-quants/`.
    /// Estimates describe warm short edits and MLX allocation, not total app
    /// memory or a guarantee that a larger model preserves every detail.
    static let recommendedModels = [
        MLXModel(
            repo: "mlx-community/gemma-3-1b-it-qat-4bit",
            estimatedSize: "0.8 GB",
            description: "Smallest download; fixes fewer mistakes",
            name: "Gemma 3 · 1B · 4-bit"
        ),
        MLXModel(
            repo: "mlx-community/Qwen3-1.7B-4bit",
            estimatedSize: "1.0 GB",
            description: "Lightweight option for Macs with less memory",
            name: "Qwen 3 · 1.7B · 4-bit"
        ),
        MLXModel(
            repo: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            estimatedSize: "2.3 GB",
            description: "Fast option; about 0.2s per short edit and 3 GB model memory on M5 Pro",
            name: "Qwen 3 · 4B · 4-bit"
        ),
        MLXModel(
            repo: "mlx-community/Qwen3.5-9B-4bit",
            estimatedSize: "6.0 GB",
            description: "Recommended balance; about 0.4s per short edit and 6 GB model memory on M5 Pro",
            name: "Qwen 3.5 · 9B · 4-bit"
        ),
        MLXModel(
            repo: "leonsarmiento/Qwen3.8-27B-3bit-mlx",
            estimatedSize: "12.7 GB",
            description: "Stronger grammar results; about 1.6s per short edit and 13 GB model memory on M5 Pro",
            name: "Qwen 3.8 · 27B · mixed 3-bit"
        )
    ]

    /// Correction models earlier versions recommended — and so may have
    /// downloaded — that `recommendedModels` has since dropped. Newest first.
    ///
    /// These are the only models "Clean up old models" may delete. The Hugging
    /// Face cache is shared with every other tool on the Mac, so "cached but not
    /// recommended" is not "ours and unused": `downloadedModels` also holds the
    /// Parakeet transcription model and any MLX model another app fetched.
    /// Cleanup used to delete all of those.
    static let retiredCorrectionModels = [
        // The 2026-07-31 benchmark (see above).
        "mlx-community/Phi-3.5-mini-instruct-4bit",
        "mlx-community/Llama-3.2-1B-Instruct-4bit",
        "mlx-community/gemma-3-1b-it-4bit",  // replaced by its QAT build
        // 2025-12-17.
        "mlx-community/Llama-3.2-3B-Instruct-4bit",
        "mlx-community/Qwen3-4B-Instruct-2507-5bit",
        // 2025-08-11.
        "mlx-community/gemma-2-2b-it-4bit"
    ]

    // Note: model/repo download logic lives in `MLXModelManager+Downloads.swift`.
    // The Parakeet download path drives the Python `parakeet_mlx` package, and the
    // selected repo is resolved from `selectedParakeetModel` (see `parakeetRepo`).

    private convenience init() {
        self.init(cacheDirectory: HuggingFaceCache.root)
        Task {
            await refreshModelList()
        }
    }

    /// The app uses `shared`, on the real cache. This exists so tests can run
    /// deletion against a temporary cache: on `shared`, a test that exercises
    /// `cleanupUnusedModels` could delete models the developer really has.
    ///
    /// Unlike `shared`, it does not scan the cache in the background — a scan
    /// finishing mid-test could re-add a model the test had just deleted. Call
    /// `refreshModelList()`.
    init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
    }

    func refreshModelList() async {
        await MainActor.run {
            self.downloadedModels.removeAll()
            self.modelSizes.removeAll()
            self.totalCacheSize = 0
        }

        guard FileManager.default.fileExists(atPath: cacheDirectory.path) else {
            logger.info("Hugging Face cache directory doesn't exist")
            return
        }

        // Perform heavy file system operations off the main thread
        let cacheDir = cacheDirectory
        // L1: prefer the forward mapping (repo → escaped dir name) as source of
        // truth so repos whose name contains literal "--" round-trip correctly.
        // We feed this lookup the recommended + currently-known set so a cached
        // model whose escaped name we've seen before resolves exactly.
        let knownEscapedToRepo: [String: String] = Self.knownReverseMap(
            extraRepos: downloadedModels
        )
        let logger = self.logger
        let result: [(String, Int64)] = await Task.detached(priority: .utility) {
            var models: [(String, Int64)] = []

            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: cacheDir,
                includingPropertiesForKeys: nil
            ) else {
                return models
            }

            for item in contents {
                guard item.lastPathComponent.hasPrefix("models--") else { continue }

                let escaped = String(item.lastPathComponent.dropFirst("models--".count))

                // Prefer the exact reverse lookup; fall back to the lossy
                // `--` → `/` rewrite and log a warning so the user can spot
                // repo names that don't round-trip.
                let modelName: String
                if let known = knownEscapedToRepo[escaped] {
                    modelName = known
                } else {
                    modelName = escaped.replacingOccurrences(of: "--", with: "/")
                    if escaped.contains("----") {
                        logger.warning("Unknown cache dir '\(escaped, privacy: .public)'; reverse mapping may be lossy")
                    }
                }

                // Check if this looks like an MLX model
                let mlxKeywords = ["mlx", "qwen", "llama", "phi", "mistral", "gemma", "starcoder", "parakeet"]
                let isLikelyMLX = mlxKeywords.contains { modelName.lowercased().contains($0) }

                if isLikelyMLX, HuggingFaceCache.completeSnapshot(in: item) {
                    let size = Self.calculateDirectorySizeSync(at: item)
                    models.append((modelName, size))
                }
            }

            return models
        }.value

        // Update UI state on main thread
        var totalSize: Int64 = 0
        for (modelName, size) in result {
            await MainActor.run {
                self.downloadedModels.insert(modelName)
                self.modelSizes[modelName] = size
            }
            totalSize += size
        }

        await MainActor.run {
            self.totalCacheSize = totalSize
        }

        logger.info("Found \(self.downloadedModels.count) MLX models, total size: \(self.formatBytes(totalSize))")
    }

    /// Builds an `escaped → repo` map for known repos (recommended + extras).
    /// Used as the source of truth when reversing the HuggingFace
    /// `models--<escaped>` directory name back to a repo (L1) — the lossy
    /// `--` → `/` rewrite is only used as a fallback.
    private static func knownReverseMap(extraRepos: Set<String>) -> [String: String] {
        var map: [String: String] = [:]
        let knownRepos: [String] = recommendedModels.map { $0.repo }
            + ParakeetModel.allCases.map { $0.rawValue }
            + Array(extraRepos)
        for repo in knownRepos {
            let escaped = repo.replacingOccurrences(of: "/", with: "--")
            map[escaped] = repo
        }
        return map
    }

    // Static version for use in detached tasks (nonisolated for background execution)
    private nonisolated static func calculateDirectorySizeSync(at url: URL) -> Int64 {
        var size: Int64 = 0

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
                size += Int64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            } catch {
                continue
            }
        }

        return size
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Returns the next preferred MLX selection after deleting `deletedRepo`.
    ///
    /// Preference order:
    /// 1. The first downloaded model in `recommendedModels`.
    /// 2. The first downloaded model in `retiredCorrectionModels`.
    /// 3. `nil`, meaning no MLX model is currently installed — callers should
    ///    surface a clear "no MLX model installed" affordance.
    ///
    /// Only correction models qualify. This used to take any other entry in
    /// `downloadedModels` first, in Set order, which could switch correction to
    /// the Parakeet transcription model or to another app's model.
    func nextSelectionAfterDeletion(deletedRepo: String) -> String? {
        let candidates = Self.recommendedModels.map(\.repo) + Self.retiredCorrectionModels
        return candidates.first { $0 != deletedRepo && downloadedModels.contains($0) }
    }

    /// The installed correction models the picker lists below the catalog:
    /// cached retired models, plus `selected` if it is not in the catalog.
    ///
    /// Not every non-catalog entry in `downloadedModels`: that includes Parakeet
    /// and whatever else is in the shared cache, none of which is a correction
    /// model to offer.
    func noLongerRecommendedModels(selected: String) -> [String] {
        let curated = Set(Self.recommendedModels.map(\.repo))
        var repos = Set(Self.retiredCorrectionModels).intersection(downloadedModels)
        if !selected.isEmpty && !curated.contains(selected) {
            repos.insert(selected)
        }
        return repos.sorted()
    }
}
