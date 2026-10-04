import XCTest
@testable import AudioWhisper

/// Tests for what "Clean up old models", the correction picker and the
/// post-deletion fallback treat as a correction model.
///
/// `downloadedModels` is every MLX-looking model in the Hugging Face cache —
/// which is shared with every other tool on the Mac — so it holds the Parakeet
/// transcription model and other apps' models alongside correction models.
/// Cleanup used to delete everything in it outside `recommendedModels`.
///
/// These run against a manager on a temporary cache, never `shared`: the repo
/// names here are real ones, and on the real cache a cleanup could delete
/// models the developer actually has.
@MainActor
final class MLXModelCleanupTests: XCTestCase {

    private let parakeet = ParakeetModel.v3Multilingual.rawValue
    private let otherAppsModel = "mlx-community/Meta-Llama-3-8B-Instruct-4bit"
    private let curated = "mlx-community/Qwen3-1.7B-4bit"
    private let retiredInUse = "mlx-community/Llama-3.2-1B-Instruct-4bit"
    private let retired = "mlx-community/Phi-3.5-mini-instruct-4bit"

    private var cacheRoot: URL!
    private var manager: MLXModelManager!

    override func setUp() async throws {
        try await super.setUp()
        cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXModelCleanupTests-\(UUID().uuidString)", isDirectory: true)
        for repo in [parakeet, otherAppsModel, curated, retiredInUse, retired] {
            let model = modelDirectory(repo)
            let revision = String(repeating: "a", count: 40)
            try HuggingFaceFixture.writeAssets(to: model.appendingPathComponent("snapshots/" + revision))
            let refs = model.appendingPathComponent("refs")
            try FileManager.default.createDirectory(at: refs, withIntermediateDirectories: true)
            try revision.write(to: refs.appendingPathComponent("main"), atomically: true, encoding: .utf8)
        }
        // The default migration keeps a user on Llama-3.2-1B if they had it.
        AppDefaults.semanticCorrectionModelRepo = retiredInUse
        manager = MLXModelManager(cacheDirectory: cacheRoot)
        await manager.refreshModelList()
    }

    override func tearDown() async throws {
        AppDefaults.defaults.removeObject(forKey: AppDefaults.Key.semanticCorrectionModelRepo.rawValue)
        manager = nil
        try? FileManager.default.removeItem(at: cacheRoot)
        try await super.tearDown()
    }

    private func modelDirectory(_ repo: String) -> URL {
        cacheRoot.appendingPathComponent("models--" + repo.replacingOccurrences(of: "/", with: "--"))
    }

    // MARK: - Cleanup

    func testTheFixtureCacheIsSeenAsFiveDownloadedModels() {
        XCTAssertEqual(manager.downloadedModels, [parakeet, otherAppsModel, curated, retiredInUse, retired])
    }

    /// The bug: this used to be four — everything but the curated model,
    /// including the Parakeet model the app transcribes with.
    func testOnlyARetiredCorrectionModelNotInUseIsUnused() {
        XCTAssertEqual(manager.unusedModels, [retired])
        XCTAssertEqual(manager.unusedModelCount, 1)
        XCTAssertEqual(manager.cleanupHelpText, "Deletes Phi-3.5-mini-instruct-4bit")
    }

    func testCleanupDeletesOnlyTheRetiredModelNotInUse() async {
        await manager.cleanupUnusedModels()

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDirectory(retired).path))
        for kept in [parakeet, otherAppsModel, curated, retiredInUse] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: modelDirectory(kept).path), "deleted \(kept)")
        }
        XCTAssertEqual(manager.unusedModelCount, 0)
    }

    func testOnceCorrectionMovesOffARetiredModelItBecomesUnused() {
        AppDefaults.semanticCorrectionModelRepo = curated

        // In `retiredCorrectionModels` order, which lists Phi first.
        XCTAssertEqual(manager.unusedModels, [retired, retiredInUse])
    }

    func testWithNothingRetiredCachedThereIsNothingToCleanUp() async {
        manager.downloadedModels = [parakeet, otherAppsModel, curated]

        XCTAssertEqual(manager.unusedModelCount, 0)
        await manager.cleanupUnusedModels()
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelDirectory(parakeet).path))
    }

    // MARK: - Picker

    func testThePickerListsRetiredModelsButNotParakeetOrOtherAppsModels() {
        XCTAssertEqual(manager.noLongerRecommendedModels(selected: retiredInUse), [retiredInUse, retired])
        XCTAssertEqual(manager.noLongerRecommendedModels(selected: curated), [retiredInUse, retired])
    }

    /// A selection outside the catalog stays visible even before it is cached,
    /// so the user can see what correction is set to and change it.
    func testThePickerKeepsAnUncachedSelectionOutsideTheCatalog() {
        manager.downloadedModels = [parakeet]

        XCTAssertEqual(manager.noLongerRecommendedModels(selected: "someone/custom-model"), ["someone/custom-model"])
        XCTAssertEqual(manager.noLongerRecommendedModels(selected: ""), [])
    }

    // MARK: - nextSelectionAfterDeletion

    func testDeletingTheSelectedModelFallsBackToACatalogModel() {
        XCTAssertEqual(manager.nextSelectionAfterDeletion(deletedRepo: retiredInUse), curated)
    }

    func testWithNoCatalogModelItFallsBackToARetiredOne() {
        manager.downloadedModels = [parakeet, otherAppsModel, retiredInUse, retired]

        XCTAssertEqual(manager.nextSelectionAfterDeletion(deletedRepo: retiredInUse), retired)
    }

    /// The bug: with these cached, the fallback used to be whichever came first
    /// in Set order — Parakeet or the other app's model.
    func testItNeverFallsBackToParakeetOrAnotherAppsModel() {
        manager.downloadedModels = [parakeet, otherAppsModel, retiredInUse]

        XCTAssertNil(manager.nextSelectionAfterDeletion(deletedRepo: retiredInUse))
    }
}
