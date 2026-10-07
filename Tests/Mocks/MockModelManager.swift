import Foundation
@testable import AudioWhisper

// Test doubles for ModelManagerTests.
//
// Split out of ModelManagerTests.swift, which had grown past 500 lines with
// roughly 200 of them being fixtures rather than assertions. Keeping the mocks
// here leaves that file as tests only, and makes it obvious when a double grows
// logic of its own — which is how a mock quietly becomes the thing under test.

// MARK: - Mock FileManager
class MockFileManager {
    var mockFiles: Set<String> = []
    var mockDirectories: Set<String> = []
    var mockFileAttributes: [String: [FileAttributeKey: Any]] = [:]
    var shouldThrowOnRemoveItem = false
    var shouldThrowOnCreateDirectory = false
    var removeItemCalled = false
    var createDirectoryCalled = false
    
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
        // Return mock application support directory
        return [URL(fileURLWithPath: "/tmp/test/ApplicationSupport")]
    }
    
    func fileExists(atPath path: String) -> Bool {
        return mockFiles.contains(path)
    }
    
    func createDirectory(at url: URL,
                         withIntermediateDirectories createIntermediates: Bool,
                         attributes: [FileAttributeKey: Any]? = nil) throws {
        createDirectoryCalled = true
        if shouldThrowOnCreateDirectory {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock create directory error"])
        }
        mockDirectories.insert(url.path)
    }
    
    func removeItem(at url: URL) throws {
        removeItemCalled = true
        if shouldThrowOnRemoveItem {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Mock remove item error"])
        }
        mockFiles.remove(url.path)
    }
    
    func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if let attributes = mockFileAttributes[path] {
            return attributes
        }
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
    }
}

// MARK: - Mock ModelManager
@Observable
class MockModelManager {
    @MainActor var downloadProgress: [WhisperModel: Double] = [:]
    @MainActor var downloadingModels: Set<WhisperModel> = []
    
    private let mockFileManager: MockFileManager
    private var downloadRequests: [WhisperModel: Bool] = [:]
    
    init(fileManager: MockFileManager) {
        self.mockFileManager = fileManager
    }
    
    var modelsDirectory: URL {
        let appSupport = mockFileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioWhisperDir = appSupport.appendingPathComponent("AudioWhisper")
        let modelsDir = audioWhisperDir.appendingPathComponent("Models")
        
        try? mockFileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true, attributes: nil)
        return modelsDir
    }
    
    nonisolated func isModelDownloaded(_ model: WhisperModel) -> Bool {
        let appSupport = mockFileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioWhisperDir = appSupport.appendingPathComponent("AudioWhisper")
        let modelsDir = audioWhisperDir.appendingPathComponent("Models")
        let modelPath = modelsDir.appendingPathComponent(model.fileName)
        return mockFileManager.fileExists(atPath: modelPath.path)
    }
    
    nonisolated func getModelPath(_ model: WhisperModel) -> URL? {
        let appSupport = mockFileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioWhisperDir = appSupport.appendingPathComponent("AudioWhisper")
        let modelsDir = audioWhisperDir.appendingPathComponent("Models")
        let modelPath = modelsDir.appendingPathComponent(model.fileName)
        return isModelDownloaded(model) ? modelPath : nil
    }
    
    nonisolated func downloadModel(_ model: WhisperModel) async throws {
        // Check if already downloading and mark as downloading
        let alreadyDownloading = await MainActor.run {
            if self.downloadingModels.contains(model) {
                return true
            }
            self.downloadingModels.insert(model)
            return false
        }
        
        if alreadyDownloading {
            throw ModelError.alreadyDownloading
        }
        
        // Clean up after download completes (will be done at the end)
        
        // Simulate actual download time
        try? await Task.sleep(for: .milliseconds(100)) // 100ms
        
        // Simulate download completion
        let destination = await MainActor.run {
            self.modelsDirectory.appendingPathComponent(model.fileName)
        }
        
        // Mark file as downloaded
        mockFileManager.mockFiles.insert(destination.path)
        
        // Set file attributes for size calculation - convert string size to bytes
        let sizeInBytes: Int64
        switch model {
        case .tiny:
            sizeInBytes = 39 * 1024 * 1024
        case .base:
            sizeInBytes = 142 * 1024 * 1024
        case .small:
            sizeInBytes = 466 * 1024 * 1024
        case .largeTurbo:
            sizeInBytes = Int64(1.5 * 1024 * 1024 * 1024)
        }
        
        mockFileManager.mockFileAttributes[destination.path] = [
            .size: sizeInBytes
        ]
        
        // Clean up download state
        await MainActor.run {
            self.downloadingModels.remove(model)
            self.downloadProgress[model] = nil
        }
    }
    
    nonisolated func deleteModel(_ model: WhisperModel) throws {
        let appSupport = mockFileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioWhisperDir = appSupport.appendingPathComponent("AudioWhisper")
        let modelsDir = audioWhisperDir.appendingPathComponent("Models")
        let modelPath = modelsDir.appendingPathComponent(model.fileName)
        
        if mockFileManager.fileExists(atPath: modelPath.path) {
            try mockFileManager.removeItem(at: modelPath)
        }
    }
    
    nonisolated func getDownloadedModels() -> [WhisperModel] {
        return WhisperModel.allCases.filter { isModelDownloaded($0) }
    }
    
    nonisolated func getTotalModelsSize() -> Int64 {
        let downloadedModels = getDownloadedModels()
        var totalSize: Int64 = 0
        
        let appSupport = mockFileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let audioWhisperDir = appSupport.appendingPathComponent("AudioWhisper")
        let modelsDir = audioWhisperDir.appendingPathComponent("Models")
        
        for model in downloadedModels {
            let modelPath = modelsDir.appendingPathComponent(model.fileName)
            if let attributes = try? mockFileManager.attributesOfItem(atPath: modelPath.path),
               let fileSize = attributes[.size] as? Int64 {
                totalSize += fileSize
            }
        }
        
        return totalSize
    }
}
