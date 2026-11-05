import XCTest
@testable import AudioWhisper

// MARK: - AppSetupHelper Tests
final class AppSetupHelperCoverageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppSetupHelperCoverageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeFile(_ name: String, created: Date) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("audio".utf8).write(to: url)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path)
        return url
    }

    func testCleanupRemovesOnlyStaleRecordings() throws {
        let now = Date()
        let stale = try makeFile("recording_1.m4a", created: now.addingTimeInterval(-25 * 3600))
        let fresh = try makeFile("recording_2.m4a", created: now.addingTimeInterval(-3600))
        let unrelated = try makeFile("notes_1.m4a", created: now.addingTimeInterval(-25 * 3600))
        let otherType = try makeFile("recording_3.wav", created: now.addingTimeInterval(-25 * 3600))

        AppSetupHelper.cleanupOldTemporaryFiles(in: directory, now: now)

        let fileManager = FileManager.default
        XCTAssertFalse(fileManager.fileExists(atPath: stale.path), "A day-old recording is crash debris")
        XCTAssertTrue(fileManager.fileExists(atPath: fresh.path), "A recent recording may still be in use")
        XCTAssertTrue(fileManager.fileExists(atPath: unrelated.path), "Only the app's own recordings are touched")
        XCTAssertTrue(fileManager.fileExists(atPath: otherType.path), "Only the app's own recordings are touched")
    }

    func testCleanupToleratesAMissingDirectory() {
        AppSetupHelper.cleanupOldTemporaryFiles(in: directory.appendingPathComponent("missing"))
    }
}

// MARK: - Semantic-correction model default (audit item B1)

/// Before B1, `SemanticCorrectionService` and `SpeechToTextService` bypassed
/// `AppDefaults.semanticCorrectionModelRepo` when the key was unset and
/// hardcoded Llama-3.2-1B, while the Dashboard badged Qwen3-1.7B as
/// RECOMMENDED. Users on the implicit default saw one model and ran another.
final class SemanticCorrectionModelDefaultTests: XCTestCase {

    func testBalancedQwenIsDefaultAndPreviousDefaultRemainsMigratable() {
        XCTAssertEqual(AppDefaults.defaultSemanticCorrectionModelRepo, "mlx-community/Qwen3.5-9B-4bit")
        XCTAssertEqual(
            AppDefaults.priorSemanticCorrectionModelRepos.first,
            "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        )
        XCTAssertEqual(
            AppSetupHelper.priorDefaultToPin(
                hasExplicitChoice: false,
                downloadedPriorDefaults: ["mlx-community/Qwen3-4B-Instruct-2507-4bit"]
            ),
            "mlx-community/Qwen3-4B-Instruct-2507-4bit"
        )
    }

    /// The bug in one assertion: the model the correction pipeline defaults to
    /// must be one the Writing page offers, or its "Recommended" badge has
    /// nothing to attach to.
    @MainActor
    func testRecommendedModelMatchesTheModelCorrectionActuallyUses() {
        let offered = MLXModelManager.recommendedModels.map(\.repo)
        XCTAssertTrue(
            offered.contains(AppDefaults.defaultSemanticCorrectionModelRepo),
            "The Writing page must list the model the correction pipeline defaults to."
        )
    }

    /// Every prior default must stay distinct from the current one, otherwise
    /// the migration below is a silent no-op.
    func testPriorDefaultsAreDistinctFromCurrent() {
        XCTAssertFalse(
            AppDefaults.priorSemanticCorrectionModelRepos
                .contains(AppDefaults.defaultSemanticCorrectionModelRepo),
            "The current default must not also be listed as a prior default"
        )
        XCTAssertEqual(
            Set(AppDefaults.priorSemanticCorrectionModelRepos).count,
            AppDefaults.priorSemanticCorrectionModelRepos.count,
            "Prior defaults must not contain duplicates"
        )
    }

    // MARK: Migration policy

    /// Existing user, never chose a model, already has a previously-shipped
    /// default on disk: keep them on it rather than silently switching them to a
    /// new default and making them download 2.3 GB.
    func testPinsPriorDefaultTheUserAlreadyHas() {
        XCTAssertEqual(
            AppSetupHelper.priorDefaultToPin(
                hasExplicitChoice: false,
                downloadedPriorDefaults: ["mlx-community/Qwen3-1.7B-4bit"]
            ),
            "mlx-community/Qwen3-1.7B-4bit"
        )
    }

    /// With several old defaults cached, keep the most recent — the input is
    /// ordered newest-first.
    func testPrefersTheMostRecentPriorDefault() {
        XCTAssertEqual(
            AppSetupHelper.priorDefaultToPin(
                hasExplicitChoice: false,
                downloadedPriorDefaults: [
                    "mlx-community/Qwen3-1.7B-4bit",
                    "mlx-community/Llama-3.2-1B-Instruct-4bit"
                ]
            ),
            "mlx-community/Qwen3-1.7B-4bit"
        )
    }

    /// Fresh install: nothing cached, no choice made — take the new default.
    func testFreshInstallGetsTheNewDefault() {
        XCTAssertNil(
            AppSetupHelper.priorDefaultToPin(
                hasExplicitChoice: false,
                downloadedPriorDefaults: []
            )
        )
    }

    /// An explicit user choice always wins, cached or not.
    func testExplicitChoiceIsNeverOverwritten() {
        XCTAssertNil(
            AppSetupHelper.priorDefaultToPin(
                hasExplicitChoice: true,
                downloadedPriorDefaults: ["mlx-community/Qwen3-1.7B-4bit"]
            )
        )
        XCTAssertNil(
            AppSetupHelper.priorDefaultToPin(
                hasExplicitChoice: true,
                downloadedPriorDefaults: []
            )
        )
    }

    // MARK: HuggingFace cache probe

    func testDetectsModelPresentInCache() throws {
        let cache = try makeTemporaryCache()
        defer { try? FileManager.default.removeItem(at: cache) }

        let repo = "mlx-community/Llama-3.2-1B-Instruct-4bit"
        try FileManager.default.createDirectory(
            at: cache.appendingPathComponent("models--mlx-community--Llama-3.2-1B-Instruct-4bit"),
            withIntermediateDirectories: true
        )

        XCTAssertTrue(AppSetupHelper.isModelInHuggingFaceCache(repo, cacheDirectory: cache))
        XCTAssertFalse(
            AppSetupHelper.isModelInHuggingFaceCache("mlx-community/Qwen3-1.7B-4bit", cacheDirectory: cache),
            "A model with no cache directory must not be reported as downloaded."
        )
    }

    /// A plain file at the snapshot path is not a usable model.
    func testFileAtModelPathIsNotTreatedAsDownloaded() throws {
        let cache = try makeTemporaryCache()
        defer { try? FileManager.default.removeItem(at: cache) }

        let path = cache.appendingPathComponent("models--mlx-community--Qwen3-1.7B-4bit")
        try Data("not a model".utf8).write(to: path)

        XCTAssertFalse(
            AppSetupHelper.isModelInHuggingFaceCache("mlx-community/Qwen3-1.7B-4bit", cacheDirectory: cache)
        )
    }

    /// The repo string becomes a path component, so traversal and absolute
    /// paths must be rejected rather than probed.
    func testRejectsUnsafeRepoIdentifiers() throws {
        let cache = try makeTemporaryCache()
        defer { try? FileManager.default.removeItem(at: cache) }

        for unsafe in ["../../etc", "/etc/passwd", "org/../../name", "org/name\u{0}"] {
            XCTAssertFalse(
                AppSetupHelper.isModelInHuggingFaceCache(unsafe, cacheDirectory: cache),
                "Unsafe repo identifier should be rejected: \(unsafe)"
            )
        }
    }

    private func makeTemporaryCache() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("hf-cache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
