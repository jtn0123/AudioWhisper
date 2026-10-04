import AppKit

/// A native menu delegate can switch to accessory mode before opening over a
/// full-screen Space. SwiftUI MenuBarExtra does not expose that lifecycle hook.
@MainActor
final class RebuildStatusController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let session: RebuildSession
    private let openWorkspace: () -> Void
    private let chooseAudio: () -> Void
    private let recordItem = NSMenuItem(title: "Record", action: nil, keyEquivalent: "")

    init(session: RebuildSession, openWorkspace: @escaping () -> Void, chooseAudio: @escaping () -> Void) {
        self.session = session
        self.openWorkspace = openWorkspace
        self.chooseAudio = chooseAudio
        super.init()
        item.button?.image = NSImage(
            systemSymbolName: "waveform.circle", accessibilityDescription: "AudioWhisper Rebuild")
        item.button?.toolTip = "AudioWhisper Rebuild"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        recordItem.action = #selector(record)
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(action("Open AudioWhisper Rebuild", selector: #selector(open)))
        menu.addItem(action("Transcribe audio file…", selector: #selector(importFile)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Rebuild", selector: #selector(quit)))
        item.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        ActivationPolicyController.shared.statusMenuWillOpen()
        recordItem.title = session.recordingActionTitle
        recordItem.isEnabled = session.canToggleRecording
        recordItem.toolTip = session.recordingBlockedReason
        menu.items[2].isEnabled = session.canImportAudio
        menu.items[2].toolTip = session.fileBlockedReason
    }

    private func action(_ title: String, selector: Selector) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        result.target = self
        return result
    }

    @objc private func record() { session.toggleRecording() }
    @objc private func open() { openWorkspace() }
    @objc private func importFile() { chooseAudio() }
    @objc private func quit() { NSApp.terminate(nil) }
}
