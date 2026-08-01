import Foundation

/// Centralized, type-safe wrapper for all UserDefaults access in the app.
/// All UserDefaults keys are defined here to prevent typos and provide documentation.
///
/// Accessors are split across concern-specific extension files:
/// - `AppDefaults+Settings.swift` — provider/model/recording/behavior settings
/// - `AppDefaults+FeatureFlags.swift` — one-time setup state and rollouts
/// - `AppDefaults+Visual.swift` — UI/visual state (waveform, intensity, icon)
///
/// Note: `UserDefaults` is thread-safe (see Apple docs), so `AppDefaults` is
/// not actor-isolated. This lets non-`@MainActor` services (audio, MLX, etc.)
/// read settings without hops to the main actor.
enum AppDefaults {
    /// Backing store. Effectively private (only used by `AppDefaults` extensions),
    /// but `internal` so extensions in other files can reach it.
    ///
    /// In production this is always `.standard`. Under test it is redirected to a
    /// per-process scratch suite — see `makeBackingStore()`.
    static let defaults: UserDefaults = makeBackingStore()

    /// Resolves the backing store, honouring the `AUDIOWHISPER_DEFAULTS_SUITE`
    /// test hook.
    ///
    /// D1/D4: the suite name gets the **process id** appended. `swift test
    /// --parallel` spawns several `xctest` processes and every one reads the same
    /// environment; without the pid they would share a single suite and race it
    /// exactly as they race the global domain today. With it, each process gets
    /// its own settings store and the settings-mutating tests stop colliding.
    ///
    /// This stays a `let` initialised once, so there is no mutable global and no
    /// data race — `AppDefaults` is deliberately not actor-isolated so
    /// non-MainActor services can read settings without a hop.
    ///
    /// For this to work, EVERY settings read/write — production and test — must
    /// go through here. Production no longer touches `UserDefaults.standard`
    /// directly (see ADR 0004); tests use `AppDefaults.defaults`.
    private static func makeBackingStore() -> UserDefaults {
        let environment = ProcessInfo.processInfo.environment
        let explicitPrefix = environment["AUDIOWHISPER_DEFAULTS_SUITE"]

        // The prefix normally comes from scripts/run-tests.sh. Relying on that
        // alone made the isolation opt-in, and CI never opted in: ci.yml called
        // `swift test --parallel` directly, so every worker fell through to
        // `.standard` and raced it. That produced 24 failures across 7 suites
        // (leaked waveformStyle, leaked enableSmartPaste, ...) which reproduced
        // on no developer machine, because everyone ran the script.
        //
        // So detect the test runner intrinsically instead: XCTest is only ever
        // loaded into a test process. Any harness that forgets the variable
        // still gets an isolated store.
        let prefix: String
        if let explicitPrefix, !explicitPrefix.isEmpty {
            prefix = explicitPrefix
        } else if NSClassFromString("XCTestCase") != nil {
            prefix = "com.audiowhisper.tests.autoscratch"
        } else {
            return .standard
        }

        let suiteName = "\(prefix).\(ProcessInfo.processInfo.processIdentifier)"
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    // MARK: - Keys

    /// All UserDefaults keys used in the app, centralized for discoverability and safety.
    enum Key: String {
        // Transcription
        case transcriptionProvider
        case selectedWhisperModel
        case selectedParakeetModel

        // Semantic Correction
        case semanticCorrectionMode
        case semanticCorrectionModelRepo

        // Recording
        case globalHotkey
        case immediateRecording
        case selectedMicrophone
        case pressAndHoldEnabled
        case pressAndHoldKeyIdentifier
        case pressAndHoldMode
        case autoBoostMicrophoneVolume

        // Visual
        case waveformStyle
        case visualIntensity
        case menuBarIconSize

        // Behavior
        case enableSmartPaste
        case playCompletionSound
        case startAtLogin

        // Data
        case transcriptionHistoryEnabled
        case transcriptionRetentionPeriod
        case maxModelStorageGB

        // Setup State
        case hasSetupParakeet
        case hasSetupLocalLLM
        case hasCompletedWelcome
        case lastWelcomeVersion
        case hasShownFirstModelUseHint
        case hasCleanedWindowState
    }

    // MARK: - Raw Access

    /// For cases where raw key access is needed (e.g., checking if a key exists)
    static func hasValue(for key: Key) -> Bool {
        defaults.object(forKey: key.rawValue) != nil
    }

    /// Remove a value from UserDefaults
    static func removeValue(for key: Key) {
        defaults.removeObject(forKey: key.rawValue)
    }

    /// Reset all app defaults to their default values
    static func resetAll() {
        for key in Key.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    /// Registers built-in default values for keys that should default to a non-nil value
    /// when the user has never set them. Called once at app launch.
    static func registerDefaults() {
        defaults.register(defaults: [
            Key.enableSmartPaste.rawValue: true,
            Key.immediateRecording.rawValue: true,
            Key.startAtLogin.rawValue: true,
            Key.playCompletionSound.rawValue: true
        ])
    }
}

// MARK: - CaseIterable for Key

extension AppDefaults.Key: CaseIterable {}
