import AppKit

@MainActor
internal class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var hotKeyManager: HotKeyManager?
    var keyboardEventHandler: KeyboardEventHandler?
    var windowController = WindowController()
    weak var recordingWindow: NSWindow?
    var recordingWindowDelegate: RecordingWindowDelegate?
    var audioRecorder: AudioEngineRecorder?
    var iconRenderer: MenuBarIconRenderer?
    var pressAndHoldMonitor: PressAndHoldKeyMonitor?
    var pressAndHoldConfiguration = PressAndHoldSettings.configuration()
    var isHoldRecordingActive = false
    /// Mirrors `RecordingViewModel.isProcessing`, kept in sync via
    /// `.transcriptionProcessingStateChanged`. Used by hotkey handlers to
    /// ignore presses while a transcription is still running (the recorder
    /// has already stopped, so checking `isRecording` alone is insufficient).
    var isTranscriptionProcessing = false

    enum HotkeyTriggerSource {
        case standardHotkey
        case pressAndHold
    }

    deinit {
        // Clean up notification observers to prevent memory leaks
        NotificationCenter.default.removeObserver(self)
    }
}
