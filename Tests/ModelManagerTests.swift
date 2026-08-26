import XCTest
import Foundation
@testable import AudioWhisper

// MARK: - ModelManagerTests
class ModelManagerTests: XCTestCase {
    var mockFileManager: MockFileManager!
    var mockModelManager: MockModelManager!
    
    override func setUp() {
        super.setUp()
        mockFileManager = MockFileManager()
        mockModelManager = MockModelManager(fileManager: mockFileManager)
    }
    
    @MainActor
    func resetModelState() {
        mockModelManager.downloadingModels.removeAll()
        mockModelManager.downloadProgress.removeAll()
    }
    
    override func tearDown() {
        mockFileManager = nil
        mockModelManager = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testModelsDirectoryCreation() {
        // Initialize the mock model manager to trigger directory creation
        _ = mockModelManager.modelsDirectory
        
        // Test that models directory is created
        XCTAssertTrue(mockFileManager.createDirectoryCalled)
        XCTAssertTrue(mockFileManager.mockDirectories.contains("/tmp/test/ApplicationSupport/AudioWhisper/Models"))
    }
    
    // MARK: - Model Download Tests
    
    func testIsModelDownloadedInitially() {
        // Initially no models should be downloaded
        for model in WhisperModel.allCases {
            XCTAssertFalse(mockModelManager.isModelDownloaded(model))
        }
    }
    
    func testDownloadModelSuccess() async {
        await resetModelState()
        let model = WhisperModel.base
        
        do {
            try await mockModelManager.downloadModel(model)
            
            // Verify model is now downloaded
            XCTAssertTrue(mockModelManager.isModelDownloaded(model))
            
            // Verify download state is cleaned up
            await MainActor.run {
                XCTAssertFalse(mockModelManager.downloadingModels.contains(model))
                XCTAssertNil(mockModelManager.downloadProgress[model])
            }
            
        } catch {
            XCTFail("Download should succeed: \(error)")
        }
    }
    
    func testDownloadModelAlreadyDownloading() async {
        await resetModelState()
        let model = WhisperModel.tiny
        
        // Start first download
        let firstDownloadTask = Task {
            try await mockModelManager.downloadModel(model)
        }
        
        // Wait a bit for first download to mark as downloading
        try? await Task.sleep(for: .milliseconds(50)) // 50ms
        
        // Try to start second download
        do {
            try await mockModelManager.downloadModel(model)
            XCTFail("Second download should fail with alreadyDownloading error")
        } catch let error as ModelError {
            XCTAssertEqual(error, ModelError.alreadyDownloading)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
        
        // Wait for first download to complete
        do {
            try await firstDownloadTask.value
        } catch {
            XCTFail("First download should succeed: \(error)")
        }
    }
    
    func testDownloadingModelsTracking() async {
        await resetModelState()
        let model = WhisperModel.small

        let startedExpectation = XCTestExpectation(description: "Download state entered")
        let finishedExpectation = XCTestExpectation(description: "Download state cleared")

        let downloadTask = Task {
            try await mockModelManager.downloadModel(model)
            finishedExpectation.fulfill()
        }

        // Poll for the downloading state rather than sleeping a fixed 20ms and
        // checking once. That single check assumed the download task would be
        // scheduled within 20ms; on a loaded CI runner it may not be, and the
        // miss is unrecoverable — startedExpectation never fulfils and the test
        // fails on the 1s timeout having tested nothing.
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            let isDownloading = await MainActor.run {
                mockModelManager.downloadingModels.contains(model)
            }
            if isDownloading {
                startedExpectation.fulfill()
                break
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

        await fulfillment(of: [startedExpectation, finishedExpectation], timeout: 1.0)
        _ = try? await downloadTask.value

        await MainActor.run {
            XCTAssertFalse(mockModelManager.downloadingModels.contains(model))
            XCTAssertNil(mockModelManager.downloadProgress[model])
        }
    }
    
    // MARK: - Model Path Tests
    
    func testGetModelPathForNonDownloadedModel() {
        let model = WhisperModel.tiny
        let path = mockModelManager.getModelPath(model)
        XCTAssertNil(path)
    }
    
    func testGetModelPathForDownloadedModel() async {
        let model = WhisperModel.base
        
        // Download model first
        do {
            try await mockModelManager.downloadModel(model)
            
            let path = mockModelManager.getModelPath(model)
            XCTAssertNotNil(path)
            XCTAssertTrue(path!.path.hasSuffix(model.fileName))
            
        } catch {
            XCTFail("Download should succeed: \(error)")
        }
    }
    
    // MARK: - Model Deletion Tests
    
    func testDeleteNonExistentModel() {
        let model = WhisperModel.base
        
        // Should not throw error when deleting non-existent model
        XCTAssertNoThrow(try mockModelManager.deleteModel(model))
        XCTAssertFalse(mockFileManager.removeItemCalled)
    }
    
    func testDeleteExistingModel() async {
        let model = WhisperModel.tiny
        
        // Download model first
        do {
            try await mockModelManager.downloadModel(model)
            XCTAssertTrue(mockModelManager.isModelDownloaded(model))
            
            // Delete model
            try mockModelManager.deleteModel(model)
            XCTAssertTrue(mockFileManager.removeItemCalled)
            XCTAssertFalse(mockModelManager.isModelDownloaded(model))
            
        } catch {
            XCTFail("Operations should succeed: \(error)")
        }
    }
    
    func testDeleteModelWithFileSystemError() async {
        let model = WhisperModel.base
        
        // Download model first
        do {
            try await mockModelManager.downloadModel(model)
            XCTAssertTrue(mockModelManager.isModelDownloaded(model))
            
            // Configure mock to throw error on removal
            mockFileManager.shouldThrowOnRemoveItem = true
            
            // Delete should throw error
            XCTAssertThrowsError(try mockModelManager.deleteModel(model))
            
        } catch {
            XCTFail("Download should succeed: \(error)")
        }
    }
    
    // MARK: - Downloaded Models Tests
    
    func testGetDownloadedModelsEmpty() {
        let downloadedModels = mockModelManager.getDownloadedModels()
        XCTAssertEqual(downloadedModels.count, 0)
    }
    
    func testGetDownloadedModelsWithSomeModels() async {
        let models = [WhisperModel.tiny, WhisperModel.base, WhisperModel.small]
        
        // Download some models
        for model in models {
            do {
                try await mockModelManager.downloadModel(model)
            } catch {
                XCTFail("Download should succeed: \(error)")
            }
        }
        
        let downloadedModels = mockModelManager.getDownloadedModels()
        XCTAssertEqual(downloadedModels.count, 3)
        XCTAssertTrue(downloadedModels.contains(WhisperModel.tiny))
        XCTAssertTrue(downloadedModels.contains(WhisperModel.base))
        XCTAssertTrue(downloadedModels.contains(WhisperModel.small))
    }
    
    // MARK: - Total Size Tests
    
    func testGetTotalModelsSizeEmpty() {
        let totalSize = mockModelManager.getTotalModelsSize()
        XCTAssertEqual(totalSize, 0)
    }
    
    func testGetTotalModelsSizeWithModels() async {
        let models = [WhisperModel.tiny, WhisperModel.base]
        
        // Download models
        for model in models {
            do {
                try await mockModelManager.downloadModel(model)
            } catch {
                XCTFail("Download should succeed: \(error)")
            }
        }
        
        let totalSize = mockModelManager.getTotalModelsSize()
        let expectedSize = Int64(39 * 1024 * 1024) + Int64(142 * 1024 * 1024)  // tiny + base in bytes
        XCTAssertEqual(totalSize, expectedSize)
    }
    
    // MARK: - Error Handling Tests
    
    func testModelErrorDescriptions() {
        XCTAssertEqual(ModelError.alreadyDownloading.errorDescription, "Model is already being downloaded")
        XCTAssertEqual(ModelError.downloadFailed.errorDescription, "Failed to download model")
        XCTAssertEqual(ModelError.modelNotFound.errorDescription, "Model file not found")
    }
    
    // MARK: - Concurrent Operations Tests
    
    func testConcurrentModelOperations() async {
        await resetModelState()
        let models = [WhisperModel.tiny, WhisperModel.base, WhisperModel.small]
        
        // Download models sequentially to avoid race conditions in tests
        for model in models {
            do {
                try await mockModelManager.downloadModel(model)
            } catch {
                XCTFail("Download should succeed: \(error)")
            }
        }
        
        // Verify all models are downloaded
        for model in models {
            XCTAssertTrue(mockModelManager.isModelDownloaded(model))
        }
        
        let downloadedModels = mockModelManager.getDownloadedModels()
        XCTAssertEqual(downloadedModels.count, 3)
    }
    
    // MARK: - Performance Tests
    
    func testDownloadModelPerformance() {
        measure {
            // Reset state before each measurement
            let expectation = self.expectation(description: "Download complete")
            Task {
                await resetModelState()
                do {
                    try await mockModelManager.downloadModel(.tiny)
                    expectation.fulfill()
                } catch {
                    XCTFail("Download should succeed: \(error)")
                    expectation.fulfill()
                }
            }
            wait(for: [expectation], timeout: 1.0)
        }
    }
    
    func testGetDownloadedModelsPerformance() async {
        // Download several models first
        let models = WhisperModel.allCases.prefix(3)
        for model in models {
            do {
                try await mockModelManager.downloadModel(model)
            } catch {
                XCTFail("Download should succeed: \(error)")
            }
        }
        
        measure {
            _ = mockModelManager.getDownloadedModels()
        }
    }
    
    func testGetTotalModelsSizePerformance() async {
        // Download several models first
        let models = WhisperModel.allCases.prefix(3)
        for model in models {
            do {
                try await mockModelManager.downloadModel(model)
            } catch {
                XCTFail("Download should succeed: \(error)")
            }
        }
        
        measure {
            _ = mockModelManager.getTotalModelsSize()
        }
    }
}
