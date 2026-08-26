import XCTest
import SwiftUI
@testable import AudioWhisper

// MARK: - ModelEntry conformance
@MainActor
final class ModelEntryConformanceTests: XCTestCase {

}

// MARK: - MLXEntry Tests
@MainActor
final class MLXEntryTests: XCTestCase {

    func testMLXEntryCreation() {
        let model = MLXModelManager.recommendedModels.first!
        let entry = MLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: false,
            statusText: nil,
            sizeText: "1GB",
            isSelected: false,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertEqual(entry.title, model.displayName)
        XCTAssertEqual(entry.subtitle, model.description)
        XCTAssertFalse(entry.isDownloaded)
        XCTAssertFalse(entry.isDownloading)
    }

    func testMLXEntryTitle() {
        let model = MLXModelManager.recommendedModels.first!
        let entry = MLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: false,
            statusText: nil,
            sizeText: "1GB",
            isSelected: false,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertEqual(entry.title, model.displayName)
    }

    func testMLXEntryStatusColorForError() {
        let model = MLXModelManager.recommendedModels.first!
        let entry = MLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: false,
            statusText: "Error: Download failed",
            sizeText: "1GB",
            isSelected: false,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertEqual(entry.statusColor, Color.red)
    }

    func testMLXEntryStatusColorForPlease() {
        let model = MLXModelManager.recommendedModels.first!
        let entry = MLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: false,
            statusText: "Please check your connection",
            sizeText: "1GB",
            isSelected: false,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertEqual(entry.statusColor, Color.red)
    }

    func testMLXEntryStatusColorForDownloading() {
        let model = MLXModelManager.recommendedModels.first!
        let entry = MLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: true,
            statusText: "Downloading...",
            sizeText: "1GB",
            isSelected: false,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertEqual(entry.statusColor, .blue)
    }

    func testMLXEntryStatusColorForNormal() {
        let model = MLXModelManager.recommendedModels.first!
        let entry = MLXEntry(
            model: model,
            isDownloaded: true,
            isDownloading: false,
            statusText: nil,
            sizeText: "1GB",
            isSelected: true,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertNil(entry.statusColor)
    }

    func testMLXEntryCaseInsensitiveErrorDetection() {
        let model = MLXModelManager.recommendedModels.first!
        let entry = MLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: false,
            statusText: "ERROR: Something went wrong",
            sizeText: "1GB",
            isSelected: false,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertEqual(entry.statusColor, Color.red)
    }
}

// MARK: - ModelEntry Protocol Tests
@MainActor
final class ModelEntryProtocolTests: XCTestCase {

    func testMLXEntryConformsToModelEntry() {
        let model = MLXModelManager.recommendedModels.first!
        let entry: ModelEntry = MLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: false,
            statusText: nil,
            sizeText: "1GB",
            isSelected: false,
            badgeText: nil,
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )

        XCTAssertFalse(entry.title.isEmpty)
        XCTAssertFalse(entry.subtitle.isEmpty)
    }

    func testModelEntryCallbacks() {
        var selectCalled = false
        var downloadCalled = false
        var deleteCalled = false

        // Retargeted at MLXEntry, the only surviving ModelEntry conformer:
        // LocalWhisperEntry was declaration-only and has been removed.
        let entry = MLXEntry(
            model: MLXModelManager.recommendedModels.first!,
            isDownloaded: false,
            isDownloading: false,
            statusText: nil,
            sizeText: nil,
            isSelected: false,
            badgeText: nil,
            onSelect: { selectCalled = true },
            onDownload: { downloadCalled = true },
            onDelete: { deleteCalled = true }
        )

        entry.onSelect()
        entry.onDownload()
        entry.onDelete()

        XCTAssertTrue(selectCalled)
        XCTAssertTrue(downloadCalled)
        XCTAssertTrue(deleteCalled)
    }
}
