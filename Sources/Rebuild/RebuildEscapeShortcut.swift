import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Esc while the recorder HUD is on screen. Registered as a hot key
    /// because the HUD is a non-activating panel that is never key, so
    /// `.onExitCommand` alone only fired after the user clicked it (C4).
    static let rebuildDismissRecorder = Self("rebuild.dismissRecorder", initial: .init(.escape))
}

/// Holds Esc only while the HUD is visible, so it is never taken from other
/// apps the rest of the time.
@MainActor
enum RebuildEscapeShortcut {
    static func install(session: RebuildSession) {
        KeyboardShortcuts.onKeyDown(for: .rebuildDismissRecorder) { [weak session] in session?.handleEscape() }
        KeyboardShortcuts.disable(.rebuildDismissRecorder)
    }

    static func recorderShown() { KeyboardShortcuts.enable(.rebuildDismissRecorder) }
    static func recorderClosed() { KeyboardShortcuts.disable(.rebuildDismissRecorder) }
}

extension RebuildSession {
    /// Esc dismisses an outcome the HUD is explaining, otherwise cancels.
    func handleEscape() {
        if recorderOutcome != nil {
            dismissOutcome()
        } else if phase.isBusy {
            cancel()
        }
    }
}
