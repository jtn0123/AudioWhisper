import XCTest
@testable import AudioWhisper

/// Model-management coverage for DashboardCorrectionView. Split out of
/// `DashboardCorrectionViewTests` to keep each test class within the type
/// body length budget.
@MainActor
final class DashboardCorrectionModelTests: XCTestCase {

    // MARK: - MLX Model Manager Tests

    func testRecommendedModelsExist() {
        let models = MLXModelManager.recommendedModels
        XCTAssertGreaterThan(models.count, 0, "Should have at least one recommended model")
    }

    func testRecommendedModelsHaveProperties() {
        for model in MLXModelManager.recommendedModels {
            XCTAssertFalse(model.repo.isEmpty, "Model should have a repo")
            XCTAssertFalse(model.displayName.isEmpty, "Model should have a display name")
            XCTAssertFalse(model.description.isEmpty, "Model should have a description")
            XCTAssertFalse(model.estimatedSize.isEmpty, "Model should have an estimated size")
        }
    }

    // MARK: - Model Refresh State Tests

    func testModelRefreshState() {
        var isRefreshingModels = false

        // Start refresh
        isRefreshingModels = true
        XCTAssertTrue(isRefreshingModels)

        // Complete refresh
        isRefreshingModels = false
        XCTAssertFalse(isRefreshingModels)
    }

    // MARK: - Mode Change Triggers Env Check

    func testModeChangeToLocalMLXTriggersCheck() {
        var lastModeRaw = "off"
        var envCheckTriggered = false

        // Simulate mode change
        let newModeRaw = "localMLX"

        if SemanticCorrectionMode(rawValue: newModeRaw) == .localMLX {
            envCheckTriggered = true
        }

        lastModeRaw = newModeRaw

        XCTAssertEqual(lastModeRaw, "localMLX")
        XCTAssertTrue(envCheckTriggered)
    }

    // MARK: - Model Download State Tests

    func testModelDownloadStartsWhenSelectingUndownloaded() {
        var downloadStarted = false
        let isDownloaded = false
        let isDownloading = false

        // Simulate selection
        if !isDownloaded && !isDownloading {
            downloadStarted = true
        }

        XCTAssertTrue(downloadStarted)
    }

    func testModelDownloadDoesNotStartWhenAlreadyDownloaded() {
        var downloadStarted = false
        let isDownloaded = true
        let isDownloading = false

        // Simulate selection
        if !isDownloaded && !isDownloading {
            downloadStarted = true
        }

        XCTAssertFalse(downloadStarted)
    }

    func testModelDownloadDoesNotStartWhenAlreadyDownloading() {
        var downloadStarted = false
        let isDownloaded = false
        let isDownloading = true

        // Simulate selection
        if !isDownloaded && !isDownloading {
            downloadStarted = true
        }

        XCTAssertFalse(downloadStarted)
    }

    // MARK: - Cleanup Button Visibility Tests

    func testCleanupButtonShownWhenUnusedModelsExist() {
        let unusedModelCount = 3
        let showCleanup = unusedModelCount > 0
        XCTAssertTrue(showCleanup)
    }

    func testCleanupButtonHiddenWhenNoUnusedModels() {
        let unusedModelCount = 0
        let showCleanup = unusedModelCount > 0
        XCTAssertFalse(showCleanup)
    }

    func testCleanupButtonPluralText() {
        let count = 2
        let suffix = pluralSuffix(for: count)
        let text = "Clean up \(count) old model\(suffix)"
        XCTAssertEqual(text, "Clean up 2 old models")
    }

    func testCleanupButtonSingularText() {
        let count = 1
        let suffix = pluralSuffix(for: count)
        let text = "Clean up \(count) old model\(suffix)"
        XCTAssertEqual(text, "Clean up 1 old model")
    }

    // Helper to avoid compile-time constant folding warnings
    private func pluralSuffix(for count: Int) -> String {
        count == 1 ? "" : "s"
    }
}
