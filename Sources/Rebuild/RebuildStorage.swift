import Foundation

/// All rebuild-owned files live outside TCC-protected personal folders.
enum RebuildStorage {
    static let directoryName = "AudioWhisper Rebuild"

    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    static var whisperDownloadBase: URL { root.appendingPathComponent("Whisper", isDirectory: true) }
    static var whisperModels: URL {
        whisperDownloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }
    static var history: URL { root.appendingPathComponent("history.store") }

    static func prepare() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
}
