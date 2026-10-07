import XCTest
@testable import AudioWhisper

@MainActor
final class ModelInstallationHealthTests: IsolatedXCTestCase {
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    func testMetadataOnlyAndInterruptedWhisperBundlesAreNotInstalled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("config.json")
        try Data("{}".utf8).write(to: config)
        XCTAssertFalse(WhisperKitStorage.hasRequiredAssets(at: directory))
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let model = directory.appendingPathComponent(name + ".mlmodelc")
            let weightsDirectory = model.appendingPathComponent("weights")
            try FileManager.default.createDirectory(at: weightsDirectory, withIntermediateDirectories: true)
            for file in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                try Data([1]).write(to: model.appendingPathComponent(file))
            }
        }
        XCTAssertTrue(WhisperKitStorage.hasRequiredAssets(at: directory))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("TextDecoder.mlmodelc/weights/weight.bin"))
        XCTAssertFalse(WhisperKitStorage.hasRequiredAssets(at: directory))
    }

    func testTruncatedHuggingFaceWeightsAreNotInstalled() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let snapshot = directory.appendingPathComponent("snapshots/abcdef")
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("refs"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "abcdef".write(to: directory.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("tokenizer.json"))
        XCTAssertFalse(HuggingFaceCache.completeSnapshot(in: directory))
        let header = Data(#"{"w":{"dtype":"U8","shape":[4],"data_offsets":[0,4]}}"#.utf8)
        var size = UInt64(header.count).littleEndian
        var weights = withUnsafeBytes(of: &size) { Data($0) }
        weights.append(header)
        try weights.write(to: snapshot.appendingPathComponent("model.safetensors"))
        XCTAssertFalse(HuggingFaceCache.completeSnapshot(in: directory))
        weights.append(contentsOf: [1, 2, 3, 4])
        try weights.write(to: snapshot.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(HuggingFaceCache.completeSnapshot(in: directory))
        try Data(#"{"weight_map":{"w":"missing.safetensors"}}"#.utf8)
            .write(to: snapshot.appendingPathComponent("model.safetensors.index.json"))
        XCTAssertFalse(HuggingFaceCache.completeSnapshot(in: directory))
    }

    func testDownloadNotificationSafelySkipsUnbundledProcess() async {
        XCTAssertNotEqual(Bundle.main.bundleURL.pathExtension, "app")
        await ModelManager.shared.sendDownloadCompletionNotification(for: .base)
    }

    func testCapacityLookupFailureReleasesDownloadAndAllowsRetry() async {
        let manager = ModelManager.shared
        let previousLimit = AppDefaults.maxModelStorageGB
        AppDefaults.maxModelStorageGB = 1000
        defer {
            AppDefaults.maxModelStorageGB = previousLimit
            manager.downloadStages.removeValue(forKey: .tiny)
        }
        for _ in 0..<2 {
            do {
                try await manager.downloadModel(.tiny, availableStorage: { throw CocoaError(.fileReadUnknown) })
                XCTFail("expected disk lookup failure")
            } catch {
                XCTAssertFalse(error is ModelError && (error as? ModelError) == .alreadyDownloading)
            }
            XCTAssertFalse(manager.downloadingModels.contains(.tiny))
            if case .failed = manager.downloadStages[.tiny] {} else { XCTFail("expected actionable failure") }
        }
    }
}
