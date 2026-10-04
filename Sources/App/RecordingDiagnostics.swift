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

@MainActor
internal enum RecordingDiagnostics {
    static func snapshot() async -> RecordingDiagnosticReport {
        let setup = RecordingSetupState.shared
        await setup.refresh()
        let permission = PermissionManager.shared
        let provider = AppDefaults.transcriptionProvider
        let model = provider == .local
            ? AppDefaults.selectedWhisperModel.rawValue : AppDefaults.selectedParakeetModel.rawValue
        let installed = provider == .local
            ? ModelManager.shared.downloadedModels.contains(AppDefaults.selectedWhisperModel)
            : setup.cachedParakeetModel == AppDefaults.selectedParakeetModel
        let requirement = setup.requirement
        return RecordingDiagnosticReport(
            build: VersionInfo.gitHash,
            launchContext: "commandLine",
            bundleIdentifier: Bundle.main.bundleIdentifier,
            provider: provider.rawValue,
            selectedVoiceModel: model,
            selectedVoiceModelInstalled: installed,
            pythonEnvironmentReady: provider == .parakeet ? setup.environmentReady : nil,
            microphonePermission: String(describing: permission.microphonePermissionState),
            smartPastePermission: String(describing: permission.accessibilityPermissionState),
            recordingShortcut: AppDefaults.globalHotkey,
            readyToRecord: requirement.isReady,
            nextStep: requirement.message
        )
    }
}
