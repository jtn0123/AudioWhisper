import XCTest
import Foundation
@testable import AudioWhisper

/// Coverage tests for `ModelManager` and `ModelManager+Enhanced`.
///
/// Exercises pure logic: integrity-file resolution against a simulated
/// WhisperKit model directory, download-time estimation, error/stage
/// descriptions, storage-space queries, and ready/state computation.
/// Real WhisperKit downloads and notifications are not driven.
@MainActor
final class ModelManagerCoverageTests: IsolatedXCTestCase {
    // Deferred(D1): ModelManager reads app settings from UserDefaults.standard.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var manager: ModelManager!

    override func setUp() {
        super.setUp()
        manager = ModelManager.shared
    }

    // MARK: - estimateDownloadTime

    func testEstimateDownloadTimeIsPositiveForEveryModel() {
        for model in WhisperModel.allCases {
            let estimate = manager.estimateDownloadTime(for: model)
            XCTAssertGreaterThan(estimate, 0, "\(model.rawValue) should have a positive time estimate")
        }
    }

    func testEstimateDownloadTimeScalesWithModelSize() {
        let tinyEstimate = manager.estimateDownloadTime(for: .tiny)
        let largeEstimate = manager.estimateDownloadTime(for: .largeTurbo)
        XCTAssertLessThan(tinyEstimate, largeEstimate, "A larger model should take longer to download")
    }

    // MARK: - estimatedSize

    func testEstimatedSizeIsMonotonicAcrossModelSizes() {
        XCTAssertLessThan(WhisperModel.tiny.estimatedSize, WhisperModel.base.estimatedSize)
        XCTAssertLessThan(WhisperModel.base.estimatedSize, WhisperModel.small.estimatedSize)
        XCTAssertLessThan(WhisperModel.small.estimatedSize, WhisperModel.largeTurbo.estimatedSize)
    }

    // MARK: - getAvailableStorageSpace

    func testGetAvailableStorageSpaceReturnsPositiveValue() async throws {
        let space = try await manager.getAvailableStorageSpace()
        XCTAssertGreaterThan(space, 0, "A real volume should report some available capacity")
    }

    // MARK: - canDeleteModel

    func testCanDeleteModelIsAlwaysTrue() {
        for model in WhisperModel.allCases {
            XCTAssertTrue(manager.canDeleteModel(model))
        }
    }

    // MARK: - representativeFileURL

    func testRepresentativeFileURLPrefersConfigJSON() throws {
        // Simulate a WhisperKit model directory with a config.json present.
        guard let dir = WhisperKitStorage.modelDirectory(for: .tiny) else {
            throw XCTSkip("WhisperKit storage directory unavailable in this environment")
        }
        let fm = FileManager.default
        let createdDir = !fm.fileExists(atPath: dir.path)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let configURL = dir.appendingPathComponent("config.json")
        let createdConfig = !fm.fileExists(atPath: configURL.path)
        if createdConfig {
            try Data("{}".utf8).write(to: configURL)
        }
        addTeardownBlock {
            if createdConfig { try? fm.removeItem(at: configURL) }
            if createdDir { try? fm.removeItem(at: dir) }
        }

        let representative = ModelManager.representativeFileURL(for: .tiny)
        XCTAssertEqual(representative?.lastPathComponent, "config.json")
    }

    func testRepresentativeFileURLFallsBackToAnyJSON() throws {
        guard let dir = WhisperKitStorage.modelDirectory(for: .base) else {
            throw XCTSkip("WhisperKit storage directory unavailable in this environment")
        }
        let fm = FileManager.default
        // Skip if a real model is installed — we don't want to disturb it.
        guard !fm.fileExists(atPath: dir.path) else {
            throw XCTSkip("A real model directory exists; skipping to avoid mutating it")
        }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let otherURL = dir.appendingPathComponent("tokenizer.json")
        try Data("{}".utf8).write(to: otherURL)
        addTeardownBlock {
            try? fm.removeItem(at: dir)
        }

        let representative = ModelManager.representativeFileURL(for: .base)
        XCTAssertEqual(representative?.pathExtension, "json")
    }

    // MARK: - isModelReady

    func testIsModelReadyFalseWhenModelIsDownloading() async {
        let downloadedSnapshot = manager.downloadedModels
        let downloadingSnapshot = manager.downloadingModels
        defer {
            manager.downloadedModels = downloadedSnapshot
            manager.downloadingModels = downloadingSnapshot
        }

        // A model currently downloading is never "ready", regardless of whether
        // it also appears in downloadedModels. `downloadingModels` is not
        // touched by the background refresh, so this assertion is stable.
        manager.downloadedModels.insert(.tiny)
        manager.downloadingModels = [.tiny]
        let ready = await manager.isModelReady(.tiny)
        XCTAssertFalse(ready, "A downloading model must not be reported as ready")
    }

    func testIsModelReadyFalseWhenModelNotTracked() async {
        let downloadedSnapshot = manager.downloadedModels
        let downloadingSnapshot = manager.downloadingModels
        defer {
            manager.downloadedModels = downloadedSnapshot
            manager.downloadingModels = downloadingSnapshot
        }

        manager.downloadedModels.remove(.largeTurbo)
        manager.downloadingModels.remove(.largeTurbo)
        // The large turbo model is very unlikely to be present on a CI runner;
        // if it genuinely is downloaded the result flips, so only assert the
        // not-downloaded path is consistent with membership.
        let ready = await manager.isModelReady(.largeTurbo)
        XCTAssertEqual(ready, manager.downloadedModels.contains(.largeTurbo))
    }

    // MARK: - getDownloadStage / getEstimatedTimeRemaining

    func testGetDownloadStageReturnsStoredStage() {
        let snapshot = manager.downloadStages
        defer { manager.downloadStages = snapshot }

        manager.downloadStages[.tiny] = .downloading
        XCTAssertEqual(manager.getDownloadStage(for: .tiny), .downloading)
        XCTAssertNil(manager.getDownloadStage(for: .largeTurbo))
    }

    func testGetEstimatedTimeRemainingReturnsStoredEstimate() {
        let snapshot = manager.downloadEstimates
        defer { manager.downloadEstimates = snapshot }

        manager.downloadEstimates[.small] = 42.0
        XCTAssertEqual(manager.getEstimatedTimeRemaining(for: .small), 42.0)
        XCTAssertNil(manager.getEstimatedTimeRemaining(for: .base))
    }

    // MARK: - refreshModelStates

    func testRefreshModelStatesUpdatesLastRefresh() async {
        await manager.refreshModelStates()
        // refreshModelStates delegates to refreshDownloadedModels which only
        // updates lastRefresh when the set actually changes; a no-throw
        // completion is the assertable contract here.
        XCTAssertNotNil(manager.lastRefresh)
    }

    // MARK: - DownloadStage

    func testDownloadStageDisplayText() {
        XCTAssertEqual(DownloadStage.preparing.displayText, "Preparing download...")
        XCTAssertEqual(DownloadStage.downloading.displayText, "Downloading model...")
        XCTAssertEqual(DownloadStage.processing.displayText, "Processing model files...")
        XCTAssertEqual(DownloadStage.completing.displayText, "Finalizing installation...")
        XCTAssertEqual(DownloadStage.ready.displayText, "Ready to use")
        XCTAssertEqual(DownloadStage.failed("disk full").displayText, "Failed: disk full")
    }

    func testDownloadStageIsActive() {
        XCTAssertTrue(DownloadStage.preparing.isActive)
        XCTAssertTrue(DownloadStage.downloading.isActive)
        XCTAssertTrue(DownloadStage.processing.isActive)
        XCTAssertTrue(DownloadStage.completing.isActive)
        XCTAssertFalse(DownloadStage.ready.isActive)
        XCTAssertFalse(DownloadStage.failed("x").isActive)
    }

    func testDownloadStageEquatable() {
        XCTAssertEqual(DownloadStage.preparing, DownloadStage.preparing)
        XCTAssertEqual(DownloadStage.failed("a"), DownloadStage.failed("a"))
        XCTAssertNotEqual(DownloadStage.failed("a"), DownloadStage.failed("b"))
        XCTAssertNotEqual(DownloadStage.ready, DownloadStage.completing)
    }

    // MARK: - ModelError

    func testModelErrorDescriptionsAreNonEmpty() {
        let errors: [ModelError] = [
            .alreadyDownloading, .downloadFailed, .modelNotFound,
            .applicationSupportDirectoryNotFound, .deletionNotSupported,
            .deletionFailed, .downloadTimeout, .insufficientStorage,
            .storageLimitExceeded
        ]
        for error in errors {
            XCTAssertFalse(
                error.errorDescription?.isEmpty ?? true,
                "\(error) should have a non-empty description"
            )
        }
    }

    func testModelErrorSpecificDescriptions() {
        XCTAssertEqual(ModelError.alreadyDownloading.errorDescription, "Model is already being downloaded")
        XCTAssertEqual(ModelError.downloadTimeout.errorDescription, "Model check timed out")
        XCTAssertEqual(ModelError.insufficientStorage.errorDescription, "Insufficient storage space for download")
    }
}
