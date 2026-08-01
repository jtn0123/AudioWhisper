import Foundation
import ServiceManagement
import AppKit
import os.log

internal class AppSetupHelper {
    static func setupApp() {
        // Only set activation policy if NSApp is available (not in unit tests)
        if Thread.isMainThread && NSApplication.shared.delegate != nil {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        setupLoginItem()
        ensurePromptFiles()
        cleanupOldTemporaryFiles()
        migrateSemanticCorrectionModelDefault()
    }

    // MARK: - Semantic-correction model migration (audit item B1)

    /// One-time migration that pins existing installs to the pre-2.0 correction
    /// model so the B1 fix doesn't silently switch them.
    ///
    /// Before B1, the two correction call sites bypassed
    /// `AppDefaults.semanticCorrectionModelRepo` whenever the key was unset and
    /// hardcoded Llama-3.2-1B, while the Dashboard displayed and badged
    /// Qwen3-1.7B as RECOMMENDED. Those call sites now honour `AppDefaults`
    /// unconditionally, which makes Qwen3 the real default.
    ///
    /// For a user who never picked a model, that flip would mean their next
    /// dictation quietly downloads a different ~1 GB model. So: if there is no
    /// explicit choice AND the legacy model is already on disk, write the legacy
    /// repo explicitly. Their behaviour is unchanged and the Dashboard now tells
    /// the truth about which model is in use. Everyone else — fresh installs, and
    /// users who never downloaded the legacy model — gets the Qwen3 default.
    ///
    /// Idempotent: writing the key makes `hasValue` true on every later launch.
    static func migrateSemanticCorrectionModelDefault() {
        let hasExplicitChoice = AppDefaults.hasValue(for: .semanticCorrectionModelRepo)
        let downloadedPriorDefaults = AppDefaults.priorSemanticCorrectionModelRepos
            .filter { isModelInHuggingFaceCache($0) }

        guard let pinned = priorDefaultToPin(
            hasExplicitChoice: hasExplicitChoice,
            downloadedPriorDefaults: downloadedPriorDefaults
        ) else { return }

        AppDefaults.semanticCorrectionModelRepo = pinned
        Logger.app.info("Pinned semantic-correction model to a previously-shipped default already on disk.")
    }

    /// Pure decision half of `migrateSemanticCorrectionModelDefault`, split out
    /// so the policy is testable without touching UserDefaults or the filesystem.
    ///
    /// Returns the repo to pin, or `nil` to let the current default apply.
    /// `downloadedPriorDefaults` must preserve
    /// `AppDefaults.priorSemanticCorrectionModelRepos` order (newest first), so
    /// a user who has several old models cached keeps the most recent one.
    static func priorDefaultToPin(
        hasExplicitChoice: Bool,
        downloadedPriorDefaults: [String]
    ) -> String? {
        guard !hasExplicitChoice else { return nil }
        return downloadedPriorDefaults.first
    }

    /// Whether `repo` has a snapshot directory in the HuggingFace hub cache.
    ///
    /// Mirrors the layout `MLXModelManager` uses (`models--org--name`) rather
    /// than reading `MLXModelManager.downloadedModels`, which is populated
    /// asynchronously after launch and would race this check.
    static func isModelInHuggingFaceCache(
        _ repo: String,
        cacheDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
    ) -> Bool {
        // Reject anything that isn't a plain `org/name` identifier before using
        // it as a path component (same guard as MLXModelManager.deleteModel).
        let allowed = repo.allSatisfy { $0.isLetter || $0.isNumber || "/._-".contains($0) }
        guard allowed, !repo.hasPrefix("/"), !repo.contains("..") else { return false }

        let escaped = repo.replacingOccurrences(of: "/", with: "--")
        let modelPath = cacheDirectory.appendingPathComponent("models--\(escaped)")

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: modelPath.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    static func setupLoginItem() {
        let startAtLogin = AppDefaults.startAtLogin

        if startAtLogin {
            // Only try to register if we're in a real app context, not in tests
            if Bundle.main.bundleIdentifier != nil && !AppEnvironment.isRunningTests {
                try? SMAppService.mainApp.register()
            }
        }
    }

    static func createMenuBarIcon() -> NSImage {
        let iconSize = getAdaptiveMenuBarIconSize()
        let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        let image = NSImage(
            systemSymbolName: "microphone.circle",
            accessibilityDescription: LocalizedStrings.Accessibility.microphoneIcon
        )?.withSymbolConfiguration(config)
        image?.isTemplate = true // This makes it adapt to menu bar appearance
        return image ?? NSImage()
    }

    private static let standardIconSize: CGFloat = 16.0  // For regular displays
    private static let notchedIconSize: CGFloat = 20.0   // For notched displays (taller menu bar)

    // Cache for icon size to avoid repeated calculations
    // Thread-safe access via lock to prevent data races
    private static let cacheLock = NSLock()
    private static var _cachedIconSize: CGFloat?
    private static var _lastMainScreenFrame: NSRect?

    /// Reset the cached icon size - useful when display configuration changes
    static func resetIconSizeCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        _cachedIconSize = nil
        _lastMainScreenFrame = nil
    }

    static func getAdaptiveMenuBarIconSize() -> CGFloat {
        // Check for user override first
        if let overrideSize = AppDefaults.menuBarIconSize,
           overrideSize > 0 {
            return CGFloat(overrideSize)
        }

        // For menu bar items, we should use the screen where the status item is located
        // not necessarily the main screen
        guard let statusItemScreen = getStatusItemScreen() else {
            // Fallback to standard size if we can't detect the screen
            return standardIconSize
        }

        // Check if screen configuration has changed by comparing frame
        let currentFrame = statusItemScreen.frame

        // Thread-safe cache access
        cacheLock.lock()
        if let cached = _cachedIconSize,
           let lastFrame = _lastMainScreenFrame,
           lastFrame == currentFrame {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // Detect if display has notch (taller menu bar) on the correct screen
        let hasNotch = detectDisplayNotchForScreen(statusItemScreen)

        // Adaptive sizing based on menu bar height
        let iconSize: CGFloat = hasNotch ? notchedIconSize : standardIconSize

        // Cache the result (thread-safe)
        cacheLock.lock()
        _cachedIconSize = iconSize
        _lastMainScreenFrame = currentFrame
        cacheLock.unlock()

        return iconSize
    }

    private static func getStatusItemScreen() -> NSScreen? {
        // Try to get the screen where the menu bar is displayed
        // In most cases, this is the screen with menu bar
        // The screen with the menu bar typically has y origin at 0
        for screen in NSScreen.screens where screen.frame.origin.y == 0 {
            return screen
        }
        // Fallback to main screen
        return NSScreen.main
    }

    private static func detectDisplayNotchForScreen(_ screen: NSScreen) -> Bool {
        // Check safe area insets (macOS 12+) - most reliable method
        // Notched displays have safe area insets at the top for the notch
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 0
        }

        // For older macOS versions, assume no notch
        return false
    }

    static func checkFirstRun() -> Bool {
        let hasExistingProvider = AppDefaults.hasValue(for: .transcriptionProvider)
        let hasCompletedWelcome = AppDefaults.hasCompletedWelcome
        let lastWelcomeVersion = AppDefaults.lastWelcomeVersion

        // Current version that includes SmartPaste feature
        let currentWelcomeVersion = "1.1" // Update this when SmartPaste feature is released

        // Show welcome for new users OR existing users who haven't seen the SmartPaste welcome
        let shouldShowWelcome = (!hasExistingProvider && !hasCompletedWelcome) || (lastWelcomeVersion != currentWelcomeVersion)

        if shouldShowWelcome {
            if !hasExistingProvider {
                // First run - default to LocalWhisper
                AppDefaults.transcriptionProvider = .local
            }
            return true
        } else if !hasExistingProvider {
            // Provider was somehow reset - default to LocalWhisper
            AppDefaults.transcriptionProvider = .local
        }

        return false
    }

    static func cleanupOldTemporaryFiles() {
        let tempDirectory = FileManager.default.temporaryDirectory

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: tempDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: []
            )
            let audioFiles = files.filter { $0.lastPathComponent.hasPrefix("recording_") && $0.pathExtension == "m4a" }

            let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago

            for file in audioFiles {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    if let creationDate = attributes[.creationDate] as? Date, creationDate < cutoffDate {
                        try FileManager.default.removeItem(at: file)
                    }
                } catch {
                    Logger.app.error("Failed to clean up file \(file.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            Logger.app.error("Failed to clean up temporary files: \(error.localizedDescription)")
        }
    }

    // MARK: - Prompt Files
    /// Ensure default prompt files exist for advanced customization
    static func ensurePromptFiles() {
        do {
            let base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("AudioWhisper/prompts", isDirectory: true)
            if !FileManager.default.fileExists(atPath: base.path) {
                try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            }

            // A4: cloud_openai_prompt.txt / cloud_gemini_prompt.txt used to be
            // written here too. The cloud providers were removed
            // (TranscriptionProvider has only .local and .parakeet), so nothing
            // ever read them — they were two junk files created in the user's
            // Application Support directory on every launch.
            let files: [(name: String, content: String)] = [
                ("local_mlx_prompt.txt", defaultLocalMLXPrompt)
            ]

            for promptFile in files {
                let url = base.appendingPathComponent(promptFile.name)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try promptFile.content.write(to: url, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            Logger.app.error("Failed to ensure prompt files: \(error.localizedDescription)")
        }
    }

    /// Shared correction prompt. Named `defaultCorrectionPrompt` since A4 —
    /// it was `defaultCloudPrompt` back when cloud providers existed.
    private static let defaultCorrectionPrompt = """
        You are a transcription corrector. Fix grammar, casing, punctuation, \
        and obvious mis-hearings that do not change meaning. Remove filler \
        words and transcribed pauses that add no meaning (e.g., 'um', 'uh', \
        'erm', 'you know', 'like' as filler; '[pause]', '(pause)', ellipses \
        for hesitations). Do not remove meaningful words. Do not summarize \
        or add content. Output only the corrected text.
        """

    private static let defaultLocalMLXPrompt = defaultCorrectionPrompt
}
