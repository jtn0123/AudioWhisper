import Foundation
import AppKit
import KeyboardShortcuts

// MARK: - KeyboardShortcuts Name
extension KeyboardShortcuts.Name {
    /// Global toggle-recording shortcut. The default value is set the first
    /// time `HotKeyManager` boots from `AppDefaults.globalHotkey` so that the
    /// user's stored preference always wins.
    static let toggleRecording = Self("audioWhisper.toggleRecording")
}

// MARK: - Parsed Hotkey
/// Result of parsing a hotkey string such as "⌘⇧Space".
internal struct ParsedHotkey {
    let key: Key?
    let modifiers: NSEvent.ModifierFlags
}

// MARK: - HotKeyManager
//
// Preserves the public surface of the original HotKey-backed manager:
//   - `init(onHotKeyPressed:)`
//   - listens for `.updateGlobalHotkey` notifications carrying a string
//   - reads `AppDefaults.globalHotkey` on initialization
//
// Internally, the manager parses the string ("⌘⇧Space" etc.) into a
// `KeyboardShortcuts.Shortcut` and registers a key-down handler with the
// KeyboardShortcuts library. AppDefaults remains the canonical store; the
// KeyboardShortcuts UserDefaults entry is a runtime mirror.
internal class HotKeyManager {
    private let onHotKeyPressed: () -> Void

    init(onHotKeyPressed: @escaping () -> Void) {
        self.onHotKeyPressed = onHotKeyPressed
        setupObservers()
        registerKeyDownHandler()
        setupInitialHotKey()
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateHotKey),
            name: .updateGlobalHotkey,
            object: nil
        )
    }

    private func registerKeyDownHandler() {
        // Remove any handler previously installed by another instance so we
        // don't accumulate them when multiple managers are created (e.g. in
        // tests). The handler we install below is the only one for the
        // `.toggleRecording` name afterwards.
        KeyboardShortcuts.removeHandler(for: .toggleRecording)
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [weak self] in
            self?.onHotKeyPressed()
        }
    }

    private func setupInitialHotKey() {
        setupHotKeyFromString(AppDefaults.globalHotkey)
    }

    @objc private func updateHotKey(_ notification: Notification) {
        if let newHotkeyString = notification.object as? String {
            setupHotKeyFromString(newHotkeyString)
        }
    }

    private func setupHotKeyFromString(_ hotkeyString: String) {
        let parsed = Self.parseHotkeyString(hotkeyString)

        guard let key = parsed.key else {
            // Invalid / empty: clear the active shortcut so nothing fires.
            KeyboardShortcuts.setShortcut(nil, for: .toggleRecording)
            return
        }

        let shortcut = KeyboardShortcuts.Shortcut(
            key.keyboardShortcutsKey,
            modifiers: parsed.modifiers
        )
        KeyboardShortcuts.setShortcut(shortcut, for: .toggleRecording)
    }

    // MARK: - Parsing
    //
    // Same string format as before ("⌘⇧Space", "⌘A", "F5", etc.). Extracted
    // as a static helper so callers (e.g. tests, future migrations) can use
    // it without instantiating the manager.
    internal static func parseHotkeyString(_ hotkeyString: String) -> ParsedHotkey {
        var modifiers: NSEvent.ModifierFlags = []
        var keyString = hotkeyString

        let modifierSymbols: [(symbol: String, flag: NSEvent.ModifierFlags)] = [
            ("⌘", .command),
            ("⇧", .shift),
            ("⌥", .option),
            ("⌃", .control)
        ]
        for entry in modifierSymbols where keyString.contains(entry.symbol) {
            modifiers.insert(entry.flag)
            keyString = keyString.replacingOccurrences(of: entry.symbol, with: "")
        }

        return ParsedHotkey(key: stringToKey(keyString), modifiers: modifiers)
    }

    /// Lookup table mapping the uppercased hotkey string fragment to a `Key`.
    /// Using a dictionary keeps `stringToKey` simple and avoids a large
    /// switch statement.
    private static let keyLookup: [String: Key] = [
        "F1": .f1, "F2": .f2, "F3": .f3, "F4": .f4, "F5": .f5,
        "F6": .f6, "F7": .f7, "F8": .f8, "F9": .f9, "F10": .f10,
        "F11": .f11, "F12": .f12, "F13": .f13, "F14": .f14, "F15": .f15,
        "F16": .f16, "F17": .f17, "F18": .f18, "F19": .f19, "F20": .f20,
        "A": .a, "B": .b, "C": .c, "D": .d, "E": .e, "F": .f, "G": .g,
        "H": .h, "I": .i, "J": .j, "K": .k, "L": .l, "M": .m, "N": .n,
        "O": .o, "P": .p, "Q": .q, "R": .r, "S": .s, "T": .t, "U": .u,
        "V": .v, "W": .w, "X": .x, "Y": .y, "Z": .z,
        "0": .zero, "1": .one, "2": .two, "3": .three, "4": .four,
        "5": .five, "6": .six, "7": .seven, "8": .eight, "9": .nine,
        "=": .equal, "-": .minus, "]": .rightBracket, "[": .leftBracket,
        "'": .quote, ";": .semicolon, "\\": .backslash, ",": .comma,
        "/": .slash, ".": .period, "`": .grave,
        "⏎": .return, "⇥": .tab, "SPACE": .space, "⌫": .delete,
        "⎋": .escape, "↑": .upArrow, "↓": .downArrow,
        "←": .leftArrow, "→": .rightArrow
    ]

    private static func stringToKey(_ keyString: String) -> Key? {
        keyLookup[keyString.uppercased()]
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        // Note: we intentionally do NOT call removeHandler here. The handler
        // captures `self` weakly, so it will no-op after deallocation. Tests
        // create many managers in sequence and the next instance's
        // `registerKeyDownHandler` will overwrite the slot.
    }
}
