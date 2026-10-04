import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension KeyboardShortcuts.Name {
    static let rebuildRecording = Self("rebuild.recording", initial: .init(.space, modifiers: [.command, .shift]))
}

struct RebuildApp: App {
    @NSApplicationDelegateAdaptor(RebuildDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra("AudioWhisper Rebuild", systemImage: "waveform.circle", isInserted: .constant(false)) {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    delegate.navigation.selection = .preferences
                    delegate.showWorkspace()
                }
                .keyboardShortcut(",")
            }
        }
    }
}

@MainActor
@Observable
final class RebuildNavigation {
    var selection: RebuildPage = .record
}

enum RebuildPage: String, CaseIterable, Identifiable {
    case record, library, models, writing, preferences
    var id: String { rawValue }
    var title: String {
        switch self {
        case .record: return "Record"
        case .library: return "Library"
        case .models: return "Models & setup"
        case .writing: return "Writing profiles"
        case .preferences: return "Preferences"
        }
    }
    var symbol: String {
        switch self {
        case .record: return "waveform"
        case .library: return "text.book.closed"
        case .models: return "shippingbox"
        case .writing: return "pencil.line"
        case .preferences: return "slider.horizontal.3"
        }
    }
}

@MainActor
final class RebuildDelegate: NSObject, NSApplicationDelegate {
    let recorder = AudioEngineRecorder()
    lazy var session = RebuildSession(services: .live(recorder: recorder))
    let navigation = RebuildNavigation()
    private var statusController: RebuildStatusController?
    private var workspace: NSWindow?
    private var workspaceDelegate: StandardWindowDelegate?
    private var overlay: NSWindow?
    private var holdOwnsSession = false
    private var holdMonitor: PressAndHoldKeyMonitor?
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppEnvironment.isRunningTests else { return }
        AppDefaults.defaults.register(defaults: [
            AppDefaults.Key.transcriptionProvider.rawValue: Arch.isAppleSilicon ? "parakeet" : "local",
            AppDefaults.Key.immediateRecording.rawValue: false,
            AppDefaults.Key.enableSmartPaste.rawValue: false,
            AppDefaults.Key.pressAndHoldEnabled.rawValue: false,
            AppDefaults.Key.startAtLogin.rawValue: false,
            AppDefaults.Key.playCompletionSound.rawValue: true
        ])
        do { try DataManager.shared.initialize() } catch {
            session.notice = "The local library could not open: \(error.localizedDescription)"
        }
        session.openSetup = { [weak self] in
            self?.navigation.selection = .models
            self?.showWorkspace()
        }
        session.showRecorder = { [weak self] in self?.showOverlay() }
        session.closeRecorder = { [weak self] in self?.overlay?.orderOut(nil) }
        statusController = RebuildStatusController(
            session: session,
            openWorkspace: { [weak self] in self?.showWorkspace() },
            chooseAudio: { [weak self] in self?.chooseAudio() })
        configureShortcuts()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .rebuildSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.configureShortcuts() } }
        Task { await session.refreshSetup() }
        showWorkspace()
    }

    func showWorkspace() {
        if let workspace {
            StandardWindow.present(workspace)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = "AudioWhisper Rebuild"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 870, height: 620)
        window.contentViewController = NSHostingController(
            rootView: RebuildRootView(
                session: session, navigation: navigation, recorder: recorder,
                importAudio: { [weak self] in self?.chooseAudio() }
            ))
        workspace = window
        workspaceDelegate = StandardWindow.open(window, frameAutosaveName: "RebuildWorkspace") { [weak self] in
            self?.workspace = nil
            self?.workspaceDelegate = nil
        }
    }

    private func showOverlay() {
        if overlay == nil {
            let window = ChromelessWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 230),
                styleMask: [.borderless], backing: .buffered, defer: false
            )
            RecordingWindowStyle.configure(window)
            window.contentViewController = NSHostingController(
                rootView: RebuildRecorderView(session: session, recorder: recorder))
            overlay = window
        }
        guard let overlay else { return }
        RecordingWindowStyle.moveToActiveScreen(overlay)
        overlay.orderFrontRegardless()
    }

    func chooseAudio() {
        guard session.canImportAudio else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.audio]
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the audio you want to transcribe."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.session.importAudio(url)
        }
    }

    private func configureShortcuts() {
        KeyboardShortcuts.removeAllHandlers()
        KeyboardShortcuts.disable(.rebuildRecording)
        holdOwnsSession = false
        holdMonitor?.stop()
        holdMonitor = nil
        if AppDefaults.defaults.bool(forKey: "rebuild.shortcutEnabled"), WindowServer.canRegisterGlobalHotkeys {
            KeyboardShortcuts.enable(.rebuildRecording)
            KeyboardShortcuts.onKeyDown(for: .rebuildRecording) { [weak self] in self?.session.toggleRecording() }
        }
        let config = PressAndHoldSettings.configuration()
        guard config.enabled, AccessibilityPermissionManager().checkPermission() else { return }
        holdMonitor = PressAndHoldKeyMonitor(
            configuration: config,
            keyDownHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    if config.mode == .hold {
                        guard !self.session.phase.isBusy else { return }
                        self.session.toggleRecording()
                        self.holdOwnsSession = self.session.phase == .starting || self.session.phase == .recording
                    } else {
                        self.session.toggleRecording()
                    }
                }
            },
            keyUpHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, config.mode == .hold, self.holdOwnsSession else { return }
                    self.holdOwnsSession = false
                    if self.session.phase == .starting { self.session.cancel() }
                    if self.session.phase == .recording { self.session.finishRecording() }
                }
            }
        )
        holdMonitor?.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWorkspace()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        session.cancel()
        holdMonitor?.stop()
        Task {
            await MLDaemonManager.shared.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

extension Notification.Name {
    static let rebuildSettingsChanged = Self("rebuild.settingsChanged")
}
