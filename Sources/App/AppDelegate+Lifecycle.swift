import AppKit
import os.log

internal extension AppDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register UserDefaults defaults - these are used when keys haven't been explicitly set
        AppDefaults.registerDefaults()

        // Skip UI initialization in test environment
        if AppEnvironment.isRunningTests {
            Logger.app.info("Test environment detected - skipping UI initialization")
            return
        }

        // Clear any corrupted window state restoration data (one-time migration)
        if !AppDefaults.hasCleanedWindowState {
            if let bundleId = Bundle.main.bundleIdentifier {
                let savedStatePath = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?
                    .appendingPathComponent("Saved Application State")
                    .appendingPathComponent("\(bundleId).savedState")
                if let path = savedStatePath, FileManager.default.fileExists(atPath: path.path) {
                    try? FileManager.default.removeItem(at: path)
                    Logger.app.info("Cleaned up corrupted window state restoration data")
                }
            }
            AppDefaults.hasCleanedWindowState = true
        }

        do {
            try DataManager.shared.initialize()
            Logger.app.info("DataManager initialized successfully")
        } catch {
            Logger.app.error("Failed to initialize DataManager: \(error.localizedDescription)")
            // App continues with in-memory fallback
        }

        Task { await UsageMetricsStore.shared.bootstrapIfNeeded() }

        AppSetupHelper.setupApp()

        audioRecorder = AudioEngineRecorder()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            iconRenderer = MenuBarIconRenderer(button: button)
            iconRenderer?.setState(.idle)
            // Note: no button action/target — assigning a menu to the
            // NSStatusItem means a click always shows the menu and never
            // invokes a button action. Recording is reachable via the menu's
            // "Start Recording" item and the global hotkey.
        }
        statusItem?.menu = makeStatusMenu()

        // Warm the menu's "Recent" cache so the first open has data.
        Task { await DashboardWindowManager.shared.refreshRecentRecordsCache() }

        hotKeyManager = HotKeyManager { [weak self] in
            self?.handleHotkey(source: .standardHotkey)
        }
        keyboardEventHandler = KeyboardEventHandler()
        configureShortcutMonitors()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        setupNotificationObservers()

        // Proactively request microphone permission at first launch
        if PermissionManager.shared.microphonePermissionState.needsRequest {
            PermissionManager.shared.proceedWithPermissionRequest()
        }

        // First-run users must always see the welcome/onboarding screen — even
        // when the default `.local` model has not been downloaded yet. The
        // first-run check therefore takes precedence over the model-missing
        // dashboard fallback below.
        if AppSetupHelper.checkFirstRun() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.showWelcomeAndSettings()
            }
            return
        }

        // Validate local model is ready before allowing use.
        // Preserves the legacy default-to-local behavior (no key set = treat as local)
        // which is also what `AppSetupHelper.checkFirstRun()` writes.
        let providerRaw = AppDefaults.defaults.string(
            forKey: AppDefaults.Key.transcriptionProvider.rawValue
        ) ?? TranscriptionProvider.local.rawValue
        if providerRaw == TranscriptionProvider.local.rawValue {
            let model = AppDefaults.selectedWhisperModel
            if !WhisperKitStorage.isModelDownloaded(model) {
                // Model not downloaded - show dashboard for download
                DashboardWindowManager.shared.showDashboardWindow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // Keep app running in menu bar
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // H7: the ML daemon is a Python subprocess; if the app exits before
        // `shutdown()` finishes, the subprocess is orphaned. Defer
        // termination until the shutdown completes.
        Task { @MainActor in
            await MLDaemonManager.shared.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        recordingWindow = nil
        recordingWindowDelegate = nil

        AppSetupHelper.cleanupOldTemporaryFiles()
    }

    func hasAPIKey(service: String, account: String) -> Bool {
        KeychainService.shared.getQuietly(service: service, account: account) != nil
    }

    func showWelcomeAndSettings() {
        let shouldOpenSettings = WelcomeWindow.showWelcomeDialog()

        if shouldOpenSettings {
            DashboardWindowManager.shared.showDashboardWindow()
        }
    }
}
