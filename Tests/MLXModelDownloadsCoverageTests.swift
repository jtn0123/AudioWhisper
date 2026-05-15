import XCTest
@testable import AudioWhisper

/// Coverage tests for `MLXModelManager` and `MLXModelManager+Downloads`.
///
/// These exercise pure logic: integrity-file path resolution, on-disk cache
/// detection against a simulated HuggingFace cache layout, integrity sidecar
/// recording, unused-model computation, and byte formatting. Network and
/// subprocess code paths are deliberately not driven.
@MainActor
final class MLXModelDownloadsCoverageTests: IsolatedXCTestCase {
    // Deferred(D1): MLXModelManager reads `selectedParakeetModel` from
    // UserDefaults.standard via AppDefaults; isolation cannot be enforced.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var manager: MLXModelManager!

    override func setUp() {
        super.setUp()
        manager = MLXModelManager.shared
    }

    // MARK: - Helpers

    /// Builds a simulated HuggingFace cache directory at the *real* path that
    /// `integrityFileURL(for:)` resolves to (which is rooted at the OS home
    /// directory and ignores the `HOME` env var). Uses a UUID-scoped repo
    /// name so it can never collide with a genuinely cached model, and
    /// registers a teardown block to remove it.
    ///
    /// Layout: `models--<escaped>/refs/main` + `snapshots/<rev>/` + `blobs/`.
    private func makeFakeHFCache(
        repo: String,
        revision: String,
        createSnapshotDir: Bool = true
    ) throws -> URL {
        let refsMain = manager.integrityFileURL(for: repo)!
        // `<hub>/models--<escaped>/refs/main` -> model dir is two levels up.
        let modelDir = refsMain.deletingLastPathComponent().deletingLastPathComponent()
        let refsDir = modelDir.appendingPathComponent("refs")
        try FileManager.default.createDirectory(at: refsDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelDir)
        }
        try revision.write(to: refsDir.appendingPathComponent("main"), atomically: true, encoding: .utf8)
        if createSnapshotDir {
            let snapDir = modelDir.appendingPathComponent("snapshots/\(revision)")
            try FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(
            at: modelDir.appendingPathComponent("blobs"),
            withIntermediateDirectories: true
        )
        return modelDir
    }

    /// A repo name guaranteed not to collide with any real cached model.
    private func uniqueRepo() -> String {
        "audiowhisper-test/coverage-\(UUID().uuidString)"
    }

    // MARK: - integrityFileURL

    func testIntegrityFileURLEscapesSlashes() {
        let url = manager.integrityFileURL(for: "mlx-community/Some-Model")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.contains("models--mlx-community--Some-Model"))
        XCTAssertTrue(url!.path.hasSuffix("refs/main"))
    }

    func testIntegrityFileURLHandlesRepoWithoutSlash() {
        let url = manager.integrityFileURL(for: "plain-model")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.contains("models--plain-model"))
    }

    // MARK: - isModelCachedOnDisk

    func testIsModelCachedOnDiskReturnsFalseWhenCacheMissing() {
        let result = manager.isModelCachedOnDisk(repo: uniqueRepo())
        XCTAssertFalse(result)
    }

    func testIsModelCachedOnDiskDetectsValidLayout() throws {
        let repo = uniqueRepo()
        // 40-char pure-hex revision, as HuggingFace produces.
        let revision = String(repeating: "a1b2c3d4", count: 5)
        _ = try makeFakeHFCache(repo: repo, revision: revision)

        let result = manager.isModelCachedOnDisk(repo: repo)
        XCTAssertTrue(result, "A complete cache layout with hex refs/main should be detected")
    }

    func testIsModelCachedOnDiskRejectsNonHexRevision() throws {
        let repo = uniqueRepo()
        // A revision containing non-hex characters must be rejected.
        _ = try makeFakeHFCache(repo: repo, revision: "not-a-hex-revision")

        let result = manager.isModelCachedOnDisk(repo: repo)
        XCTAssertFalse(result, "Non-hex refs/main contents must be rejected")
    }

    func testIsModelCachedOnDiskRejectsEmptyRevision() throws {
        let repo = uniqueRepo()
        _ = try makeFakeHFCache(repo: repo, revision: "")

        let result = manager.isModelCachedOnDisk(repo: repo)
        XCTAssertFalse(result, "Empty refs/main contents must be rejected")
    }

    func testIsModelCachedOnDiskRejectsMissingSnapshotDir() throws {
        let repo = uniqueRepo()
        let revision = String(repeating: "ff00ff00", count: 5)
        _ = try makeFakeHFCache(repo: repo, revision: revision, createSnapshotDir: false)

        let result = manager.isModelCachedOnDisk(repo: repo)
        XCTAssertFalse(result, "Missing snapshot directory must be rejected")
    }

    // MARK: - recordIntegrity

    func testRecordIntegrityNoOpsWhenRefsMainMissing() {
        // No cache directory exists; recordIntegrity should silently no-op.
        XCTAssertNoThrow(manager.recordIntegrity(for: uniqueRepo()))
    }

    func testRecordIntegrityWritesSidecarForExistingRefsFile() throws {
        let repo = uniqueRepo()
        let revision = String(repeating: "deadbeef", count: 5)
        _ = try makeFakeHFCache(repo: repo, revision: revision)

        manager.recordIntegrity(for: repo)

        let refsMain = manager.integrityFileURL(for: repo)!
        let sidecar = refsMain.appendingPathExtension("audiowhisper-integrity")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sidecar.path),
            "recordIntegrity should write a sidecar next to refs/main"
        )
    }

    // MARK: - unusedModelCount / recommended models

    func testUnusedModelCountIsZeroForOnlyRecommendedModels() {
        let snapshot = manager.downloadedModels
        defer { manager.downloadedModels = snapshot }

        manager.downloadedModels = Set(MLXModelManager.recommendedModels.map { $0.repo })
        XCTAssertEqual(manager.unusedModelCount, 0)
    }

    func testUnusedModelCountCountsNonRecommendedModels() {
        let snapshot = manager.downloadedModels
        defer { manager.downloadedModels = snapshot }

        manager.downloadedModels = ["some-org/unexpected-model", "another-org/odd-model"]
        XCTAssertEqual(manager.unusedModelCount, 2)
    }

    // MARK: - formatBytes

    func testFormatBytesProducesNonEmptyOutput() {
        XCTAssertFalse(manager.formatBytes(0).isEmpty)
        XCTAssertFalse(manager.formatBytes(123_456_789).isEmpty)
        XCTAssertTrue(manager.formatBytes(5 * 1024 * 1024 * 1024).contains("GB"))
    }
}
