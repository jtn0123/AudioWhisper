import Foundation
import os.log

// Centralized logging for AudioWhisper
internal extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.audiowhisper.app"

    static let modelManager = Logger(subsystem: subsystem, category: "ModelManager")
    static let audioRecorder = Logger(subsystem: subsystem, category: "AudioRecorder")
    static let microphoneVolume = Logger(subsystem: subsystem, category: "MicrophoneVolume")
    static let speechToText = Logger(subsystem: subsystem, category: "SpeechToText")
    static let keychain = Logger(subsystem: subsystem, category: "Keychain")
    static let app = Logger(subsystem: subsystem, category: "App")
    static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let dataManager = Logger(subsystem: subsystem, category: "DataManager")
    static let paste = Logger(subsystem: subsystem, category: "Paste")
    static let fileSystem = Logger(subsystem: subsystem, category: "FileSystem")
}

// MARK: - Logging Helpers

extension String {
    /// Returns a copy with the current user's home directory replaced by `<home>`,
    /// for safe inclusion in log messages. Use this on any path string before
    /// passing it to a logger.
    var redactingHomeDirectory: String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return self }
        return self.replacingOccurrences(of: home, with: "<home>")
    }
}
