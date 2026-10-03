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

    /// Audit item E3: the integrity record moved OUT of the model's own
    /// directory into app-owned storage, precisely so a process that can rewrite
    /// the model cannot rewrite the hash vouching for it. This test therefore
    /// asserts the record is usable, not where it sits — and asserts it is *not*
    /// beside `refs/main`, which is the behaviour E3 removed.
    func testRecordIntegrityMakesTheModelVerifiableWithoutWritingBesideIt() throws {
        let repo = uniqueRepo()
        let revision = String(repeating: "deadbeef", count: 5)
        _ = try makeFakeHFCache(repo: repo, revision: revision)

        manager.recordIntegrity(for: repo)

        let refsMain = manager.integrityFileURL(for: repo)!

        // The record must exist somewhere the app owns — proved by verify()
        // succeeding, and by tampering then failing.
        XCTAssertNoThrow(try ModelIntegrity.verify(at: refsMain),
                         "recordIntegrity should leave the model verifiable")

        let legacySidecar = refsMain.appendingPathExtension("audiowhisper-integrity")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: legacySidecar.path),
            "E3: the hash must not be written next to the model it vouches for"
        )

        try "tampered".write(to: refsMain, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ModelIntegrity.verify(at: refsMain),
                             "a recorded hash must still catch tampering")
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

    // MARK: - Download process (audit #1: command injection; pinning)

    /// The repo travels as its own argv entry to the bundled script — never
    /// interpolated into Python source — so a hostile name stays inert data.
    /// This replaces a test that grepped this file's source for
    /// `repo = sys.argv[1]`, which stopped meaning anything once the Python
    /// moved out of Swift string literals and into download_model.py.
    func testDownloadProcessPassesRepoAsASingleArgument() throws {
        let hostile = "evil/repo\"); import os; os.system(\"touch /tmp/pwned"
        let process = try XCTUnwrap(manager.makeDownloadProcess(pythonPath: "/usr/bin/python3", repo: hostile))
        let args = try XCTUnwrap(process.arguments)

        XCTAssertEqual(args.count, 2, "an unpinned repo gets script + repo, nothing else")
        XCTAssertEqual(URL(fileURLWithPath: args[0]).lastPathComponent, "download_model.py")
        XCTAssertEqual(args[1], hostile, "the repo must arrive verbatim as one argument")
        XCTAssertFalse(args.contains("-c"), "no inline Python source")
    }

    func testDownloadProcessPinsShippedModels() throws {
        let repo = ParakeetModel.v3Multilingual.rawValue
        let process = try XCTUnwrap(manager.makeDownloadProcess(pythonPath: "/usr/bin/python3", repo: repo))

        XCTAssertEqual(Array((process.arguments ?? []).dropFirst()), [repo, try XCTUnwrap(ModelPins.revision(for: repo))])
    }

    func testDownloadProcessUsesTheAllowlistedEnvironment() throws {
        let process = try XCTUnwrap(manager.makeDownloadProcess(pythonPath: "/usr/bin/python3", repo: uniqueRepo()))
        XCTAssertEqual(process.environment, MLDaemonManager.daemonEnvironment())
    }

    /// A bundle without download_model.py must not leave the row spinning:
    /// the busy flag clears and the row says why, since a retry cannot help.
    func testAMissingDownloadScriptClearsTheBusyStateWithAnError() async {
        let repo = uniqueRepo()
        manager.isDownloading[repo] = true
        defer {
            manager.isDownloading[repo] = nil
            manager.downloadProgress[repo] = nil
        }

        await manager.reportMissingDownloadScript(for: repo)

        XCTAssertEqual(manager.isDownloading[repo], false)
        XCTAssertEqual(manager.downloadProgress[repo], "Error: Download script missing from the app bundle")
    }
}
