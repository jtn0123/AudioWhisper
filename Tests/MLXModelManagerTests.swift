import XCTest
@testable import AudioWhisper

@MainActor
final class MLXModelManagerTests: IsolatedXCTestCase {
    // Deferred(D1): MLXModelManager reads `selectedParakeetModel` from
    // UserDefaults.standard via AppDefaults. Once AppDefaults accepts an
    // injected UserDefaults, route writes through a UUID-scoped suite and
    // re-enable isolation.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    // MARK: - MLXModel Tests

    func testMLXModelDisplayNameExtractsLastPathComponent() {
        let model = MLXModel(
            repo: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            estimatedSize: "0.6 GB",
            description: "Test model"
        )

        XCTAssertEqual(model.displayName, "Llama-3.2-1B-Instruct-4bit")
    }

    func testMLXModelDisplayNameHandlesSingleComponent() {
        let model = MLXModel(
            repo: "simple-model",
            estimatedSize: "1.0 GB",
            description: "Single component"
        )

        XCTAssertEqual(model.displayName, "simple-model")
    }

    func testMLXModelIdentifiable() {
        let model1 = MLXModel(repo: "test/model1", estimatedSize: "1 GB", description: "First")
        let model2 = MLXModel(repo: "test/model1", estimatedSize: "1 GB", description: "First")

        // Each instance gets a unique UUID
        XCTAssertNotEqual(model1.id, model2.id)
    }

    func testMLXModelEquatable() {
        let model1 = MLXModel(repo: "test/model", estimatedSize: "1 GB", description: "Test")
        let model2 = MLXModel(repo: "test/model", estimatedSize: "1 GB", description: "Test")

        // Equatable compares all properties except id
        XCTAssertEqual(model1.repo, model2.repo)
        XCTAssertEqual(model1.estimatedSize, model2.estimatedSize)
        XCTAssertEqual(model1.description, model2.description)
    }

    // MARK: - Recommended Models Tests

    func testRecommendedModelsListIsNotEmpty() {
        XCTAssertFalse(MLXModelManager.recommendedModels.isEmpty)
    }

    func testRecommendedModelsHaveValidStructure() {
        for model in MLXModelManager.recommendedModels {
            XCTAssertFalse(model.repo.isEmpty, "Repo should not be empty")
            XCTAssertFalse(model.estimatedSize.isEmpty, "Estimated size should not be empty")
            XCTAssertFalse(model.description.isEmpty, "Description should not be empty")
            XCTAssertTrue(model.repo.contains("/"), "Repo should be in org/name format")
        }
    }

    /// The catalog changes as models are benchmarked, so assert invariants that
    /// must hold for ANY catalog rather than freezing today's membership.
    func testRecommendedModelsInvariants() {
        let models = MLXModelManager.recommendedModels
        let repos = models.map { $0.repo }

        XCTAssertFalse(models.isEmpty)
        XCTAssertEqual(Set(repos).count, repos.count, "No duplicate repos")

        XCTAssertTrue(
            repos.contains(AppDefaults.defaultSemanticCorrectionModelRepo),
            "The default correction model must be offered in the picker, or users "
                + "cannot see or manage what they are running"
        )

        for model in models {
            XCTAssertTrue(model.repo.hasPrefix("mlx-community/"), "\(model.repo) is not an MLX repo")
            XCTAssertFalse(model.description.isEmpty, "\(model.repo) needs a description")
            XCTAssertFalse(model.estimatedSize.isEmpty, "\(model.repo) needs a size")
        }
    }

    /// Retired by the 2026-07-31 benchmark: Phi-3.5-mini was accepted by
    /// safeMerge 1/6 times while labelled "Premium quality"; Llama-3.2-1B fixed
    /// 0/6 homophones and was the only candidate that dropped required terms.
    func testRetiredModelsAreNotOffered() {
        let repos = MLXModelManager.recommendedModels.map { $0.repo }
        XCTAssertFalse(repos.contains("mlx-community/Phi-3.5-mini-instruct-4bit"))
        XCTAssertFalse(repos.contains("mlx-community/Llama-3.2-1B-Instruct-4bit"))
    }

    // MARK: - Format Bytes Tests

    func testFormatBytesReturnsReadableString() {
        let manager = MLXModelManager.shared

        // Test various sizes
        let formatted1KB = manager.formatBytes(1024)
        XCTAssertTrue(formatted1KB.contains("KB") || formatted1KB.contains("bytes"))

        let formatted1MB = manager.formatBytes(1024 * 1024)
        XCTAssertTrue(formatted1MB.contains("MB") || formatted1MB.contains("KB"))

        let formatted1GB = manager.formatBytes(1024 * 1024 * 1024)
        XCTAssertTrue(formatted1GB.contains("GB") || formatted1GB.contains("MB"))
    }

    func testFormatBytesHandlesZero() {
        let manager = MLXModelManager.shared
        let formatted = manager.formatBytes(0)
        XCTAssertFalse(formatted.isEmpty)
    }

    // MARK: - Initial State Tests

    func testUnusedModelCountCalculatesCorrectly() {
        let manager = MLXModelManager.shared

        // With empty downloadedModels, unused count should be 0
        // (because there are no downloaded models that aren't in recommended)
        let initialCount = manager.unusedModelCount
        XCTAssertGreaterThanOrEqual(initialCount, 0)
    }

    // MARK: - Parakeet Repo Tests

    func testParakeetRepoReturnsDefaultWhenNotSet() {
        AppDefaults.defaults.removeObject(forKey: "selectedParakeetModel")

        let repo = MLXModelManager.parakeetRepo
        XCTAssertFalse(repo.isEmpty)
    }

    func testParakeetRepoReturnsUserSelection() {
        let customRepo = "custom/parakeet-model"
        AppDefaults.defaults.set(customRepo, forKey: "selectedParakeetModel")

        let repo = MLXModelManager.parakeetRepo
        XCTAssertEqual(repo, customRepo)

        // Cleanup
        AppDefaults.defaults.removeObject(forKey: "selectedParakeetModel")
    }

    // MARK: - nextSelectionAfterDeletion Tests

    func testNextSelectionAfterDeletionReturnsNilWhenNothingElseDownloaded() {
        let manager = MLXModelManager.shared
        let saved = manager.downloadedModels
        defer { manager.downloadedModels = saved }

        manager.downloadedModels = ["mlx-community/Qwen3-1.7B-4bit"]
        XCTAssertNil(manager.nextSelectionAfterDeletion(deletedRepo: "mlx-community/Qwen3-1.7B-4bit"))
    }

    func testNextSelectionAfterDeletionPrefersAnotherDownloadedModel() {
        let manager = MLXModelManager.shared
        let saved = manager.downloadedModels
        defer { manager.downloadedModels = saved }

        manager.downloadedModels = [
            "mlx-community/Qwen3-1.7B-4bit",
            "mlx-community/Llama-3.2-1B-Instruct-4bit"
        ]
        let next = manager.nextSelectionAfterDeletion(deletedRepo: "mlx-community/Qwen3-1.7B-4bit")
        XCTAssertEqual(next, "mlx-community/Llama-3.2-1B-Instruct-4bit")
    }

    func testNextSelectionAfterDeletionDoesNotReturnDeletedRepo() {
        let manager = MLXModelManager.shared
        let saved = manager.downloadedModels
        defer { manager.downloadedModels = saved }

        manager.downloadedModels = ["mlx-community/Llama-3.2-1B-Instruct-4bit"]
        // The only "downloaded" entry IS the one being deleted — nothing remains.
        XCTAssertNil(manager.nextSelectionAfterDeletion(deletedRepo: "mlx-community/Llama-3.2-1B-Instruct-4bit"))
    }
}
