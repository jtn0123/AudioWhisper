import Carbon
import CoreGraphics
import Foundation

/// Finds the virtual key that types a character in the user's keyboard layout.
///
/// `kVK_ANSI_V` names a physical key position, not a letter. On Dvorak that key
/// types "." — so a synthetic ⌘ plus `kVK_ANSI_V` is not Paste there, and on
/// AZERTY-family layouts it can land on a different shortcut entirely. Menu
/// key equivalents are matched against the character the layout produces with
/// ⌘ held, so the key code is resolved the same way: through `UCKeyTranslate`
/// on the command layer. That also covers "Dvorak – QWERTY ⌘", whose command
/// layer is QWERTY.
enum KeyboardLayoutKeyCode {
    /// Maps a virtual key code to the character it types with ⌘ held.
    typealias Translate = (CGKeyCode) -> String?

    /// The first layout that can type `character` wins. Layouts are searched in
    /// order: the active one, then the ASCII-capable layout macOS itself uses
    /// for shortcuts while a non-Latin layout (Russian, Greek, …) is active.
    static func keyCode(for character: String, layouts: [Translate]) -> CGKeyCode? {
        let target = character.lowercased()
        let preferred = CGKeyCode(kVK_ANSI_V)
        for translate in layouts {
            // Keep the conventional key when it already types the character.
            if translate(preferred)?.lowercased() == target { return preferred }
            if let code = (0..<128).map({ CGKeyCode($0) }).first(where: { translate($0)?.lowercased() == target }) {
                return code
            }
        }
        return nil
    }

    /// The key to post with ⌘ for Paste. Falls back to the ANSI position when
    /// no layout data is available (some input methods expose none).
    @MainActor
    static func pasteKeyCode() -> CGKeyCode {
        keyCode(for: "v", layouts: liveLayouts()) ?? CGKeyCode(kVK_ANSI_V)
    }

    @MainActor
    static func liveLayouts() -> [Translate] {
        let sources = [TISCopyCurrentKeyboardLayoutInputSource(), TISCopyCurrentASCIICapableKeyboardLayoutInputSource()]
        return sources.compactMap { $0?.takeRetainedValue() }.compactMap(translator(for:))
    }

    static func translator(for source: TISInputSource) -> Translate? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let keyboardType = UInt32(LMGetKbdType())
        let commandLayer = UInt32((cmdKey >> 8) & 0xFF)
        return { code in
            layoutData.withUnsafeBytes { bytes -> String? in
                guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDisplay), commandLayer, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count, &length, &characters)
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: characters, count: length)
            }
        }
    }
}
