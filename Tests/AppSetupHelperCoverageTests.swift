import XCTest
import AppKit
@testable import AudioWhisper

// MARK: - AppSetupHelper Tests
@MainActor
final class AppSetupHelperCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): checkFirstRun reads/writes AppDefaults (UserDefaults.standard).
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var originalProvider: Any?
    private var originalCompletedWelcome: Any?
    private var originalWelcomeVersion: Any?
    private var originalIconSize: Any?

    override func setUp() {
        super.setUp()
        originalProvider = AppDefaults.defaults.object(forKey: AppDefaults.Key.transcriptionProvider.rawValue)
        originalCompletedWelcome = AppDefaults.defaults.object(forKey: AppDefaults.Key.hasCompletedWelcome.rawValue)
        originalWelcomeVersion = AppDefaults.defaults.object(forKey: AppDefaults.Key.lastWelcomeVersion.rawValue)
        originalIconSize = AppDefaults.defaults.object(forKey: AppDefaults.Key.menuBarIconSize.rawValue)
    }

    override func tearDown() {
        restore(originalProvider, AppDefaults.Key.transcriptionProvider)
        restore(originalCompletedWelcome, AppDefaults.Key.hasCompletedWelcome)
        restore(originalWelcomeVersion, AppDefaults.Key.lastWelcomeVersion)
        restore(originalIconSize, AppDefaults.Key.menuBarIconSize)
        AppSetupHelper.resetIconSizeCache()
        super.tearDown()
    }

    private func restore(_ value: Any?, _ key: AppDefaults.Key) {
        if let value = value {
            AppDefaults.defaults.set(value, forKey: key.rawValue)
        } else {
            AppDefaults.defaults.removeObject(forKey: key.rawValue)
        }
    }

    // MARK: - createMenuBarIcon

    func testCreateMenuBarIconReturnsTemplateImage() {
        let icon = AppSetupHelper.createMenuBarIcon()
        XCTAssertNotNil(icon)
        XCTAssertTrue(icon.isTemplate)
    }

    // MARK: - Icon Size

    func testAdaptiveIconSizeWithUserOverride() {
        AppDefaults.menuBarIconSize = 19.0
        AppSetupHelper.resetIconSizeCache()
        XCTAssertEqual(AppSetupHelper.getAdaptiveMenuBarIconSize(), 19.0)
    }

    func testAdaptiveIconSizeIgnoresZeroOverride() {
        AppDefaults.menuBarIconSize = 0.0
        AppSetupHelper.resetIconSizeCache()
        // Zero override is rejected; falls back to a positive computed size.
        XCTAssertGreaterThan(AppSetupHelper.getAdaptiveMenuBarIconSize(), 0)
    }

    func testAdaptiveIconSizeWithoutOverrideIsPositive() {
        AppDefaults.menuBarIconSize = nil
        AppSetupHelper.resetIconSizeCache()
        XCTAssertGreaterThan(AppSetupHelper.getAdaptiveMenuBarIconSize(), 0)
    }

    func testAdaptiveIconSizeIsCachedOnSecondCall() {
        AppDefaults.menuBarIconSize = nil
        AppSetupHelper.resetIconSizeCache()
        let first = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let second = AppSetupHelper.getAdaptiveMenuBarIconSize()
        XCTAssertEqual(first, second)
    }

    func testResetIconSizeCacheDoesNotCrash() {
        AppSetupHelper.resetIconSizeCache()
        AppSetupHelper.resetIconSizeCache()
    }

    // MARK: - checkFirstRun

    func testCheckFirstRunForBrandNewUserDefaultsToLocalProvider() {
        AppDefaults.removeValue(for: .transcriptionProvider)
        AppDefaults.removeValue(for: .hasCompletedWelcome)
        AppDefaults.removeValue(for: .lastWelcomeVersion)

        let shouldShowWelcome = AppSetupHelper.checkFirstRun()

        XCTAssertTrue(shouldShowWelcome)
        XCTAssertEqual(AppDefaults.transcriptionProvider, .local)
    }

    func testCheckFirstRunWhenWelcomeAlreadyCurrentReturnsFalse() {
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.hasCompletedWelcome = true
        AppDefaults.lastWelcomeVersion = "1.1"

        let shouldShowWelcome = AppSetupHelper.checkFirstRun()

        XCTAssertFalse(shouldShowWelcome)
        XCTAssertEqual(AppDefaults.transcriptionProvider, .parakeet)
    }

    func testCheckFirstRunForExistingUserOnOldWelcomeVersion() {
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.hasCompletedWelcome = true
        AppDefaults.lastWelcomeVersion = "1.0"

        let shouldShowWelcome = AppSetupHelper.checkFirstRun()

        XCTAssertTrue(shouldShowWelcome)
    }

    // MARK: - File Helpers

    func testEnsurePromptFilesDoesNotCrash() {
        AppSetupHelper.ensurePromptFiles()
    }

    func testCleanupOldTemporaryFilesDoesNotCrash() {
        AppSetupHelper.cleanupOldTemporaryFiles()
    }

    func testSetupLoginItemDoesNotCrash() {
        AppSetupHelper.setupLoginItem()
    }
}

// MARK: - Semantic-correction model default (audit item B1)

/// Before B1, `SemanticCorrectionService` and `SpeechToTextService` bypassed
/// `AppDefaults.semanticCorrectionModelRepo` when the key was unset and
/// hardcoded Llama-3.2-1B, while the Dashboard badged Qwen3-1.7B as
/// RECOMMENDED. Users on the implicit default saw one model and ran another.
final class SemanticCorrectionModelDefaultTests: XCTestCase {

    /// The bug in one assertion: the value the correction pipeline resolves must
    /// be the value the UI recommends.
    func testRecommendedModelMatchesTheModelCorrectionActuallyUses() {
        XCTAssertTrue(
            DashboardCorrectionView.testableIsRecommended(
                repo: AppDefaults.defaultSemanticCorrectionModelRepo
            ),
            "The Dashboard must badge the same model the correction pipeline defaults to."
        )
        XCTAssertEqual(
            DashboardCorrectionView.testableDefaultModelRepo(),
            AppDefaults.defaultSemanticCorrectionModelRepo
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
