import AVFoundation
import KeyboardShortcuts

@MainActor
enum RebuildDiagnostics {
    static func snapshot(context: String = "commandLine") async -> RecordingDiagnosticReport {
        let session = RebuildSession(
            services: RebuildSessionServices(
                start: { _ in false }, stop: { nil }, cancel: {},
                transcribe: { _, _, _ in TranscriptionResult(text: "", correctionOutcome: nil) },
                copy: { _ in }, save: { _, _, _ in }))
        await session.refreshSetup()
        let provider = AppDefaults.transcriptionProvider
        let model =
            provider == .local
            ? AppDefaults.selectedWhisperModel.rawValue : AppDefaults.selectedParakeetModel.rawValue
        return RecordingDiagnosticReport(
            build: VersionInfo.gitHash, launchContext: context, bundleIdentifier: Bundle.main.bundleIdentifier,
            provider: provider.rawValue, selectedVoiceModel: model,
            selectedVoiceModelInstalled: session.readiness.modelInstalled,
            pythonEnvironmentReady: provider == .parakeet ? session.readiness.runtimeReady : nil,
            microphonePermission: String(describing: AVCaptureDevice.authorizationStatus(for: .audio)),
            smartPastePermission: AccessibilityPermissionManager().checkPermission() ? "granted" : "notEnabled",
            recordingShortcut: AppDefaults.defaults.bool(forKey: "rebuild.shortcutEnabled")
                ? KeyboardShortcuts.getShortcut(for: .rebuildRecording)?.description ?? "unassigned" : "disabled",
            readyToRecord: session.readiness.ready, nextStep: session.readiness.nextStep)
    }
}
