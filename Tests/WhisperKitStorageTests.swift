import XCTest
@testable import AudioWhisper

final class WhisperKitStorageTests: XCTestCase {

    // MARK: - Storage Directory Tests

    func testStorageDirectoryReturnsValidPath() {
        let dir = WhisperKitStorage.storageDirectory()
        XCTAssertNotNil(dir)
        XCTAssertTrue(dir?.path.contains("huggingface") ?? false)
        XCTAssertTrue(dir?.path.contains("whisperkit") ?? false)
    }

    func testStorageDirectoryContainsExpectedComponents() {
        let dir = WhisperKitStorage.storageDirectory()
        XCTAssertNotNil(dir)

        let path = dir?.path ?? ""
        XCTAssertTrue(path.contains("huggingface/models"))
        XCTAssertTrue(path.contains("argmaxinc"))
        XCTAssertTrue(path.contains("whisperkit-coreml"))
    }

    // MARK: - Model Directory Tests

    func testModelDirectoryConstruction() {
        let dir = WhisperKitStorage.modelDirectory(for: .base)
        XCTAssertNotNil(dir)
    }

    func testModelDirectoryContainsModelName() {
        let dir = WhisperKitStorage.modelDirectory(for: .base)
        XCTAssertNotNil(dir)
        // Model directory should contain the WhisperKit model name
        XCTAssertTrue(dir?.lastPathComponent.isEmpty == false)
    }

    func testDifferentModelsHaveDifferentPaths() {
        let tinyDir = WhisperKitStorage.modelDirectory(for: .tiny)
        let baseDir = WhisperKitStorage.modelDirectory(for: .base)
        let smallDir = WhisperKitStorage.modelDirectory(for: .small)
        let largeDir = WhisperKitStorage.modelDirectory(for: .largeTurbo)

        XCTAssertNotNil(tinyDir)
        XCTAssertNotNil(baseDir)
        XCTAssertNotNil(smallDir)
        XCTAssertNotNil(largeDir)

        // All paths should be unique
        let paths = [tinyDir?.path, baseDir?.path, smallDir?.path, largeDir?.path].compactMap { $0 }
        let uniquePaths = Set(paths)
        XCTAssertEqual(paths.count, uniquePaths.count, "Each model should have a unique path")
    }

    // MARK: - Model Download Check Tests

    func testIsModelDownloadedForNonExistentPath() {
        // Using default FileManager - models may or may not be downloaded
        // This test verifies the function doesn't crash for any model
        for model in WhisperModel.allCases {
            // Should not crash regardless of download state
            _ = WhisperKitStorage.isModelDownloaded(model)
        }
        XCTAssertTrue(true, "isModelDownloaded should not crash")
    }

    func testLocalModelPathDoesNotCrash() {
        // This test verifies localModelPath doesn't crash for any model
        for model in WhisperModel.allCases {
            _ = WhisperKitStorage.localModelPath(for: model)
        }
        XCTAssertTrue(true, "localModelPath should not crash")
    }

    // MARK: - Ensure Base Directory Exists Tests

    func testEnsureBaseDirectoryExistsDoesNotThrow() {
        // This should not throw even if the directory already exists
        XCTAssertNoThrow(WhisperKitStorage.ensureBaseDirectoryExists())
    }

    func testEnsureBaseDirectoryExistsMultipleTimes() {
        // Calling multiple times should not cause issues
        for _ in 0..<5 {
            WhisperKitStorage.ensureBaseDirectoryExists()
        }
        XCTAssertTrue(true, "Multiple calls should not crash")
    }

    // MARK: - All Models Tests

    func testAllModelsHaveValidPaths() {
        for model in WhisperModel.allCases {
            let dir = WhisperKitStorage.modelDirectory(for: model)
            XCTAssertNotNil(dir, "Model \(model) should have a valid directory")
        }
    }

    func testAllModelsHaveNonEmptyWhisperKitModelName() {
        for model in WhisperModel.allCases {
            XCTAssertFalse(model.whisperKitModelName.isEmpty, "Model \(model) should have a non-empty WhisperKit model name")
        }
    }

    // MARK: - WhisperModel Tests

    func testWhisperModelDisplayNames() {
        for model in WhisperModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty, "Model \(model) should have a display name")
        }
    }

    func testWhisperModelRawValueRoundTrip() {
        for model in WhisperModel.allCases {
            let rawValue = model.rawValue
            let restored = WhisperModel(rawValue: rawValue)
            XCTAssertEqual(restored, model)
        }
    }

    func testWhisperModelFileSizes() {
        for model in WhisperModel.allCases {
            XCTAssertFalse(model.fileSize.isEmpty, "Model \(model) should have a file size description")
        }
    }

    // MARK: - Path Consistency Tests

    func testStorageAndModelDirectoriesAreRelated() {
        guard let storageDir = WhisperKitStorage.storageDirectory(),
              let modelDir = WhisperKitStorage.modelDirectory(for: .base) else {
            XCTFail("Directories should not be nil")
            return
        }

        // Model directory should be inside storage directory
        XCTAssertTrue(modelDir.path.hasPrefix(storageDir.path))
    }

    func testModelDirectoryPathStructure() {
        for model in WhisperModel.allCases {
            guard let dir = WhisperKitStorage.modelDirectory(for: model) else {
                XCTFail("Model directory should not be nil for \(model)")
                continue
            }

            // Path should contain the model's WhisperKit name
            let modelName = model.whisperKitModelName
            XCTAssertTrue(dir.lastPathComponent == modelName || dir.path.contains(modelName),
                         "Path should contain model name for \(model)")
        }
    }
}
