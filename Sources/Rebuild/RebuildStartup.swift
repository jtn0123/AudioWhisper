import Foundation

/// Coordinates first launch independently of native window/menu construction.
/// The app supplies its real effects; fixtures exercise the same ordering and
/// setup routing without registering global keys or requesting permissions.
@MainActor
enum RebuildStartup {
    struct Effects {
        var initializeHistory: () throws -> Void
        var migrateSettings: () -> Void
        var installMenu: () -> Void
        var configureShortcuts: () -> Void
        var showWorkspace: () -> Void
        var showRecorder: () -> Void
        var closeRecorder: () -> Void
    }

    static func configure(
        session: RebuildSession, navigation: RebuildNavigation, effects: Effects
    ) {
        AppDefaults.defaults.register(defaults: [
            AppDefaults.Key.transcriptionProvider.rawValue: Arch.isAppleSilicon ? "parakeet" : "local",
            AppDefaults.Key.immediateRecording.rawValue: false,
            AppDefaults.Key.enableSmartPaste.rawValue: false,
            AppDefaults.Key.pressAndHoldEnabled.rawValue: false,
            AppDefaults.Key.startAtLogin.rawValue: false,
            AppDefaults.Key.playCompletionSound.rawValue: true
        ])
        effects.migrateSettings()
        do { try effects.initializeHistory() } catch {
            session.notice = "The local library could not open: \(error.localizedDescription)"
        }
        let showWorkspace = effects.showWorkspace
        session.openSetup = {
            navigation.selection = .models
            showWorkspace()
        }
        session.showRecorder = effects.showRecorder
        session.closeRecorder = effects.closeRecorder
        effects.installMenu()
        effects.configureShortcuts()
        Task { await session.refreshSetup() }
        effects.showWorkspace()
    }
}
