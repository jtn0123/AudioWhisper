import AppKit
import SwiftUI

/// The welcome window, shown on first run and from "Help / Welcome".
///
/// It is an ordinary window. It used to run modally (`NSApp.runModal`), which
/// froze the rest of the app while it was open: the menu bar icon would not
/// open its menu, so a welcome window that had fallen behind another app could
/// only be found again with Mission Control.
@MainActor
internal enum WelcomeWindow {
    private static var window: NSWindow?
    private static var delegate: StandardWindowDelegate?

    /// Shows the welcome window, or brings it forward if it is already open.
    /// "Get started" closes it and posts `.welcomeCompleted`, which opens the
    /// recording checklist.
    static func show() {
        if let window {
            StandardWindow.present(window)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: LayoutMetrics.Welcome.windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = NSHostingController(rootView: WelcomeView())
        window.title = "Welcome to AudioWhisper"

        // However it closes — "Get started" or the close button — the user
        // has now seen it. Closing with the button used to leave
        // `lastWelcomeVersion` unset, so it came back at every launch.
        self.window = window
        delegate = StandardWindow.open(window, frameAutosaveName: nil) {
            markSeen()
            WelcomeWindow.window = nil
            WelcomeWindow.delegate = nil
        }
    }

    /// "Get started": records the welcome as seen, opens recording setup and
    /// closes the welcome window.
    static func finish() {
        // Only a first run has no provider yet. "Help / Welcome" reopens this
        // screen for existing users, and finishing it used to set `.local`
        // regardless — so reading the welcome again switched a Parakeet user
        // to Whisper.
        if !AppDefaults.hasValue(for: .transcriptionProvider) {
            AppDefaults.transcriptionProvider = .local
        }
        markSeen()

        // AppDelegate opens recording setup on this.
        NotificationCenter.default.post(name: .welcomeCompleted, object: nil)
        window?.close()
    }

    /// Records that this version of the welcome has been seen, so
    /// `AppSetupHelper.checkFirstRun()` does not show it again.
    static func markSeen() {
        AppDefaults.hasCompletedWelcome = true
        AppDefaults.lastWelcomeVersion = AppSetupHelper.currentWelcomeVersion
    }
}
