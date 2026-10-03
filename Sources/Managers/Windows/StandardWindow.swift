import AppKit

/// What the Dashboard, History and Welcome windows share: they are ordinary
/// Mac windows. They stay on the Space they were opened on, can go full
/// screen, reopen where they were left, and while any of them is open the app
/// has a Dock icon and a ⌘-Tab entry (`ActivationPolicyController`).
///
/// The Dashboard and History windows used to be configured
/// `[.moveToActiveSpace, .fullScreenAuxiliary]`: they jumped to whichever Space
/// was active each time the app was, and opened as overlays on top of another
/// app's full-screen window — panel behaviour, on windows that are not panels.
@MainActor
internal enum StandardWindow {
    static let collectionBehavior: NSWindow.CollectionBehavior = [.fullScreenPrimary]

    /// Applies the shared configuration. With a `frameAutosaveName`, the window
    /// reopens at the size and position it was closed at.
    static func configure(_ window: NSWindow, frameAutosaveName: String?) {
        window.collectionBehavior = collectionBehavior
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.center()
        // Replaces the centring above with the saved frame, if there is one.
        // AppKit itself moves a frame saved on a since-unplugged display back
        // onto a screen.
        if let frameAutosaveName {
            window.setFrameAutosaveName(frameAutosaveName)
        }
    }

    /// Configures a new window, runs `onClose` when it closes, and shows it.
    /// Returns the window's delegate for the caller to keep: a window holds
    /// its delegate weakly.
    static func open(_ window: NSWindow, frameAutosaveName: String?,
                     onClose: @escaping () -> Void) -> StandardWindowDelegate {
        configure(window, frameAutosaveName: frameAutosaveName)
        let delegate = StandardWindowDelegate(onClose: onClose)
        window.delegate = delegate
        present(window)
        return delegate
    }

    /// Shows the windows. Tests swap in one that activates nothing.
    static var presenter: WindowPresenter = .shared

    /// Brings `window` to the front, restoring it if minimised, and makes
    /// AudioWhisper the active app — on a desktop, not over another app's
    /// full-screen window (`WindowPresenter`).
    static func present(_ window: NSWindow) {
        presenter.present(window)
    }
}

/// Delegate for a `StandardWindow`: tells `ActivationPolicyController` the
/// window has gone, then runs its owner's cleanup.
internal final class StandardWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            ActivationPolicyController.shared.windowWillClose(window)
        }
        onClose()
    }
}
