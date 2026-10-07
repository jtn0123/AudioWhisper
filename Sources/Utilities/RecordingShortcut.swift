import AppKit
import KeyboardShortcuts

enum RecordingShortcut {
    static func display(_ value: String) -> String {
        HotKeyManager.parseHotkeyString(value).key == nil ? "Set shortcut" : value
    }

    static func spoken(_ value: String) -> String {
        guard HotKeyManager.parseHotkeyString(value).key != nil else { return "Set a recording shortcut in Input settings" }
        return value.replacingOccurrences(of: "⌘", with: "Command ")
            .replacingOccurrences(of: "⇧", with: "Shift ")
            .replacingOccurrences(of: "⌥", with: "Option ")
            .replacingOccurrences(of: "⌃", with: "Control ")
    }

    @MainActor
    static func apply(_ value: String, to item: NSMenuItem) {
        let parsed = HotKeyManager.parseHotkeyString(value)
        guard let key = parsed.key else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.setShortcut(KeyboardShortcuts.Shortcut(key.keyboardShortcutsKey, modifiers: parsed.modifiers))
    }
}
