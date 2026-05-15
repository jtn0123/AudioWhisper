import Foundation
import Observation
import os.log

internal struct MLXModel: Identifiable, Equatable {
    let id = UUID()
    let repo: String
    let estimatedSize: String
    let description: String
    
    var displayName: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
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
            ?? ParakeetModel.v3Multilingual.rawValue
    }
    
    // Curated list of quality MLX models for semantic correction
    static let recommendedModels = [
        MLXModel(
            repo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            estimatedSize: "0.6 GB",
            description: "Fastest, good for simple corrections"
        ),
        MLXModel(
            repo: "mlx-community/gemma-3-1b-it-4bit",
            estimatedSize: "0.9 GB",
            description: "Google's efficient small model"
        ),
        MLXModel(
            repo: "mlx-community/Qwen3-1.7B-4bit",
            estimatedSize: "1.0 GB",
            description: "Best balance of speed and quality"
        ),
        MLXModel(
            repo: "mlx-community/Phi-3.5-mini-instruct-4bit",
            estimatedSize: "2.4 GB",
            description: "Premium quality correction"
        )
    ]
    
    // Note: model/repo download logic lives in `MLXModelManager+Downloads.swift`.
    // The Parakeet download path drives the Python `parakeet_mlx` package, and the
    // selected repo is resolved from `selectedParakeetModel` (see `parakeetRepo`).

    private init() {
        self.cacheDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        Task {
            await refreshModelList()
        }
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

                // Convert directory name back to repo format
                let modelName = item.lastPathComponent
                    .replacingOccurrences(of: "models--", with: "")
                    .replacingOccurrences(of: "--", with: "/")

                // Check if this looks like an MLX model
                let mlxKeywords = ["mlx", "qwen", "llama", "phi", "mistral", "gemma", "starcoder", "parakeet"]
                let isLikelyMLX = mlxKeywords.contains { modelName.lowercased().contains($0) }

                if isLikelyMLX {
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
}
