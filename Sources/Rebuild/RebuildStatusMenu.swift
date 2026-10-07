import AppKit

/// Actual native menu contents and commands, independent of the status-bar
/// item and its Space/global-shortcut lifecycle.
@MainActor
final class RebuildStatusMenu: NSObject {
    let menu = NSMenu()
    let recordItem = NSMenuItem(title: "Record", action: nil, keyEquivalent: "")
    private let session: RebuildSession
    private let openWorkspace: () -> Void
    private let chooseAudio: () -> Void

    init(session: RebuildSession, openWorkspace: @escaping () -> Void, chooseAudio: @escaping () -> Void) {
        self.session = session
        self.openWorkspace = openWorkspace
        self.chooseAudio = chooseAudio
        super.init()
        menu.autoenablesItems = false
        recordItem.action = #selector(record)
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(action("Open AudioWhisper Rebuild", selector: #selector(open)))
        menu.addItem(action("Transcribe audio file…", selector: #selector(importFile)))
        menu.addItem(.separator())
        menu.addItem(action("Quit Rebuild", selector: #selector(quit)))
    }

    func refresh() {
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
