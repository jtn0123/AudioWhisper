import Foundation
@testable import AudioWhisper

/// Protocol for MLXModelManager to enable mocking
@MainActor
protocol MLXModelManaging {
    var downloadedModels: Set<String> { get }
    var modelSizes: [String: Int64] { get }
    var isDownloading: [String: Bool] { get }
    var downloadProgress: [String: String] { get }
    var totalCacheSize: Int64 { get }
    var unusedModelCount: Int { get }

    func refreshModelList() async
    func downloadModel(_ repo: String) async
    func ensureParakeetModel() async
    func downloadParakeetModel() async
    func deleteModel(_ repo: String) async
    func cleanupUnusedModels() async
    func formatBytes(_ bytes: Int64) -> String
}

/// Mock implementation for testing MLX model management
@MainActor
final class MockMLXModelManager: MLXModelManaging {
    // MARK: - State

    var downloadedModels: Set<String> = []
    var modelSizes: [String: Int64] = [:]
    var isDownloading: [String: Bool] = [:]
    var downloadProgress: [String: String] = [:]
    var totalCacheSize: Int64 = 0

    var unusedModelCount: Int {
        let recommendedRepos = Set(MLXModelManager.recommendedModels.map { $0.repo })
        return downloadedModels.filter { !recommendedRepos.contains($0) }.count
    }

    // MARK: - Call Tracking

    var refreshModelListCallCount = 0
    var downloadModelCallCount = 0
    var downloadModelLastRepo: String?
    var ensureParakeetModelCallCount = 0
    var downloadParakeetModelCallCount = 0
    var deleteModelCallCount = 0
    var deleteModelLastRepo: String?
    var cleanupUnusedModelsCallCount = 0

    // MARK: - Configurable Behavior

    var shouldSimulateDownloadDelay: TimeInterval = 0
    var shouldFailDownload = false
    var downloadError: Error?

    // MARK: - Protocol Methods

    func refreshModelList() async {
        refreshModelListCallCount += 1
    }

    func downloadModel(_ repo: String) async {
        downloadModelCallCount += 1
        downloadModelLastRepo = repo

        if shouldSimulateDownloadDelay > 0 {
            isDownloading[repo] = true
            downloadProgress[repo] = "Downloading..."
            try? await Task.sleep(for: .milliseconds(Int(shouldSimulateDownloadDelay * 1000)))
        }

        if shouldFailDownload {
            isDownloading[repo] = false
            downloadProgress[repo] = "Error: \(downloadError?.localizedDescription ?? "Download failed")"
        } else {
            isDownloading[repo] = false
            downloadProgress.removeValue(forKey: repo)
            downloadedModels.insert(repo)
        }
    }

    func ensureParakeetModel() async {
        ensureParakeetModelCallCount += 1
        let repo = MLXModelManager.parakeetRepo
        if !downloadedModels.contains(repo) {
            await downloadParakeetModel()
        }
    }

    func downloadParakeetModel() async {
        downloadParakeetModelCallCount += 1
        let repo = MLXModelManager.parakeetRepo

        if shouldSimulateDownloadDelay > 0 {
            isDownloading[repo] = true
            try? await Task.sleep(for: .milliseconds(Int(shouldSimulateDownloadDelay * 1000)))
        }

        if !shouldFailDownload {
            downloadedModels.insert(repo)
        }
        isDownloading[repo] = false
    }

    func deleteModel(_ repo: String) async {
        deleteModelCallCount += 1
        deleteModelLastRepo = repo
        downloadedModels.remove(repo)
        modelSizes.removeValue(forKey: repo)
    }

    func cleanupUnusedModels() async {
        cleanupUnusedModelsCallCount += 1
        let recommendedRepos = Set(MLXModelManager.recommendedModels.map { $0.repo })
        downloadedModels = downloadedModels.filter { recommendedRepos.contains($0) }
    }

    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Test Helpers

    func reset() {
        downloadedModels = []
        modelSizes = [:]
        isDownloading = [:]
        downloadProgress = [:]
        totalCacheSize = 0

        refreshModelListCallCount = 0
        downloadModelCallCount = 0
        downloadModelLastRepo = nil
        ensureParakeetModelCallCount = 0
        downloadParakeetModelCallCount = 0
        deleteModelCallCount = 0
        deleteModelLastRepo = nil
        cleanupUnusedModelsCallCount = 0

        shouldSimulateDownloadDelay = 0
        shouldFailDownload = false
        downloadError = nil
    }

    func setModelInstalled(_ repo: String, size: Int64 = 1_000_000_000) {
        downloadedModels.insert(repo)
        modelSizes[repo] = size
        totalCacheSize = modelSizes.values.reduce(0, +)
    }

    func setModelDownloading(_ repo: String, progress: String = "Downloading...") {
        isDownloading[repo] = true
        downloadProgress[repo] = progress
    }
}
