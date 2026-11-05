import AppKit
import KeyboardShortcuts

/// A native menu delegate can switch to accessory mode before opening over a
/// full-screen Space. SwiftUI MenuBarExtra does not expose that lifecycle hook.
@MainActor
final class RebuildStatusController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let contents: RebuildStatusMenu
    private let session: RebuildSession
    private(set) var icon: RebuildStatusIcon?

    init(session: RebuildSession, openWorkspace: @escaping () -> Void, chooseAudio: @escaping () -> Void) {
        self.session = session
        self.contents = RebuildStatusMenu(session: session, openWorkspace: openWorkspace, chooseAudio: chooseAudio)
        super.init()
        contents.menu.delegate = self
        item.menu = contents.menu
        trackSessionState()
    }

    /// Re-arms after every change: `withObservationTracking` fires once.
    private func trackSessionState() {
        let next = withObservationTracking {
            RebuildStatusIcon.resolve(
                phase: session.phase, meeting: session.meetings.activity,
                failureVisible: session.recorderOutcome?.isFailure == true)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.trackSessionState() }
        }
        apply(next)
    }

    private func apply(_ next: RebuildStatusIcon) {
        guard next != icon, let button = item.button else { return }
        icon = next
        let image = NSImage(systemSymbolName: next.symbol, accessibilityDescription: next.label)
        // Template images take `contentTintColor`; nil restores the menu bar's own colour.
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = next.isAlert ? .systemRed : nil
        button.toolTip = next.label
        button.setAccessibilityLabel(next.label)
    }

    func menuWillOpen(_ menu: NSMenu) {
        ActivationPolicyController.shared.statusMenuWillOpen()
        contents.recordItem.setShortcut(
            for: AppDefaults.defaults.bool(forKey: "rebuild.shortcutEnabled") ? .rebuildRecording : nil)
        // AppKit handles the menu equivalent while tracking. Pausing Carbon
        // avoids buffering a second invocation until the menu closes.
        KeyboardShortcuts.disable(.rebuildRecording)
        contents.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        if AppDefaults.defaults.bool(forKey: "rebuild.shortcutEnabled"), WindowServer.canRegisterGlobalHotkeys {
            KeyboardShortcuts.enable(.rebuildRecording)
        }
    }

}
