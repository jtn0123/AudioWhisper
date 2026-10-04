import Foundation
import os.log

internal enum WhisperKitStorage {
    private static func baseDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    static func storageDirectory(fileManager: FileManager = .default) -> URL? {
        baseDirectory(fileManager: fileManager)
    }

    static func modelDirectory(for model: WhisperModel, fileManager: FileManager = .default) -> URL? {
        baseDirectory(fileManager: fileManager)?
            .appendingPathComponent(model.whisperKitModelName, isDirectory: true)
    }

    static func isModelDownloaded(_ model: WhisperModel, fileManager: FileManager = .default) -> Bool {
        guard let modelDirectory = modelDirectory(for: model, fileManager: fileManager) else { return false }

        return hasRequiredAssets(at: modelDirectory, fileManager: fileManager)
    }

    static func hasRequiredAssets(at directory: URL, fileManager: FileManager = .default) -> Bool {
        // These are the three models WhisperKit.loadModels actually opens.
        ["MelSpectrogram", "AudioEncoder", "TextDecoder"].allSatisfy { name in
            let compiled = directory.appendingPathComponent(name + ".mlmodelc")
            let package = directory.appendingPathComponent(name + ".mlpackage")
            for candidate in [compiled, package] {
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue,
                      fileManager.isReadableFile(atPath: candidate.path) else { continue }
                let required = candidate.pathExtension == "mlmodelc"
                    ? ["coremldata.bin", "model.mil", "weights/weight.bin"]
                    : ["Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"]
                if required.allSatisfy({ relative in
                    guard let values = try? candidate.appendingPathComponent(relative).resolvingSymlinksInPath()
                        .resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
                    return values.isRegularFile == true && (values.fileSize ?? 0) > 0
                }) { return true }
            }
            return false
        }
    }

    static func localModelPath(for model: WhisperModel, fileManager: FileManager = .default) -> String? {
        guard isModelDownloaded(model, fileManager: fileManager),
              let url = modelDirectory(for: model, fileManager: fileManager) else {
            return nil
        }
        return url.path
    }

    static func ensureBaseDirectoryExists(fileManager: FileManager = .default) {
        guard let baseDirectory = baseDirectory(fileManager: fileManager) else { return }
        do {
            try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } catch {
            Logger.fileSystem.error("Failed to create WhisperKit base directory at \(baseDirectory.path.redactingHomeDirectory): \(error.localizedDescription)")
        }
    }
}
