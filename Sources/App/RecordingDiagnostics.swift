import Foundation

/// Read-only support output. No transcript, credentials, or history is included.
internal struct RecordingDiagnosticReport: Codable {
    let build: String
    let launchContext: String
    let bundleIdentifier: String?
    let provider: String
    let selectedVoiceModel: String
    let selectedVoiceModelInstalled: Bool
    let pythonEnvironmentReady: Bool?
    let microphonePermission: String
    let smartPastePermission: String
    let recordingShortcut: String
    let readyToRecord: Bool
    let nextStep: String
}
