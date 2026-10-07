import AppKit
import KeyboardShortcuts

/// A native menu delegate can switch to accessory mode before opening over a
/// full-screen Space. SwiftUI MenuBarExtra does not expose that lifecycle hook.
@MainActor
final class RebuildStatusController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let contents: RebuildStatusMenu

    init(session: RebuildSession, openWorkspace: @escaping () -> Void, chooseAudio: @escaping () -> Void) {
        self.contents = RebuildStatusMenu(session: session, openWorkspace: openWorkspace, chooseAudio: chooseAudio)
        super.init()
        item.button?.image = NSImage(
            systemSymbolName: "waveform.circle", accessibilityDescription: "AudioWhisper Rebuild")
        item.button?.toolTip = "AudioWhisper Rebuild"
        contents.menu.delegate = self
        item.menu = contents.menu
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
