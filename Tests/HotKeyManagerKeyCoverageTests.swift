import XCTest
import AppKit
import KeyboardShortcuts
@testable import AudioWhisper

// MARK: - Key Enum Bridge Tests
final class HotKeyManagerKeyCoverageTests: XCTestCase {

    func testLetterKeysBridgeToKeyboardShortcutsKey() {
        let letters: [(Key, KeyboardShortcuts.Key)] = [
            (.a, .a), (.b, .b), (.c, .c), (.m, .m), (.n, .n), (.z, .z)
        ]
        for (key, expected) in letters {
            XCTAssertEqual(key.keyboardShortcutsKey, expected)
        }
    }

    func testDigitKeysBridgeToKeyboardShortcutsKey() {
        let digits: [(Key, KeyboardShortcuts.Key)] = [
            (.zero, .zero), (.one, .one), (.five, .five), (.nine, .nine)
        ]
        for (key, expected) in digits {
            XCTAssertEqual(key.keyboardShortcutsKey, expected)
        }
    }

    func testFunctionKeysBridgeToKeyboardShortcutsKey() {
        let functions: [(Key, KeyboardShortcuts.Key)] = [
            (.f1, .f1), (.f5, .f5), (.f12, .f12), (.f20, .f20)
        ]
        for (key, expected) in functions {
            XCTAssertEqual(key.keyboardShortcutsKey, expected)
        }
    }

    func testPunctuationAndArrowKeysBridge() {
        let punctuation: [(Key, KeyboardShortcuts.Key)] = [
            (.return, .return), (.tab, .tab), (.space, .space),
            (.delete, .delete), (.escape, .escape), (.equal, .equal),
            (.minus, .minus), (.leftBracket, .leftBracket),
            (.rightBracket, .rightBracket), (.quote, .quote),
            (.semicolon, .semicolon), (.backslash, .backslash),
            (.comma, .comma), (.slash, .slash), (.period, .period),
            (.grave, .backtick), (.upArrow, .upArrow),
            (.downArrow, .downArrow), (.leftArrow, .leftArrow),
            (.rightArrow, .rightArrow)
        ]
        for (key, expected) in punctuation {
            XCTAssertEqual(key.keyboardShortcutsKey, expected)
        }
    }

    func testEveryAlphabetKeyBridgesNonNil() {
        let allLetters: [Key] = [
            .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
            .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z
        ]
        for key in allLetters {
            // keyboardShortcutsKey returns a non-optional; just exercise it.
            _ = key.keyboardShortcutsKey
        }
    }

    func testKeyIsHashable() {
        let set: Set<Key> = [.a, .a, .b, .space]
        XCTAssertEqual(set.count, 3)
    }
}

// MARK: - HotKeyManager.parseHotkeyString Tests
final class HotKeyManagerParseCoverageTests: XCTestCase {

    func testParseCommandLetter() {
        let parsed = HotKeyManager.parseHotkeyString("⌘A")
        XCTAssertEqual(parsed.key, .a)
        XCTAssertTrue(parsed.modifiers.contains(.command))
        XCTAssertFalse(parsed.modifiers.contains(.shift))
    }

    func testParseAllModifiers() {
        let parsed = HotKeyManager.parseHotkeyString("⌘⇧⌥⌃B")
        XCTAssertEqual(parsed.key, .b)
        XCTAssertTrue(parsed.modifiers.contains(.command))
        XCTAssertTrue(parsed.modifiers.contains(.shift))
        XCTAssertTrue(parsed.modifiers.contains(.option))
        XCTAssertTrue(parsed.modifiers.contains(.control))
    }

    func testParseSpaceKeyword() {
        let parsed = HotKeyManager.parseHotkeyString("⌘⇧Space")
        XCTAssertEqual(parsed.key, .space)
        XCTAssertTrue(parsed.modifiers.contains(.command))
        XCTAssertTrue(parsed.modifiers.contains(.shift))
    }

    func testParseFunctionKeyWithoutModifiers() {
        let parsed = HotKeyManager.parseHotkeyString("F5")
        XCTAssertEqual(parsed.key, .f5)
        XCTAssertTrue(parsed.modifiers.isEmpty)
    }

    func testParseSpecialSymbolKeys() {
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘⏎").key, .return)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘⇥").key, .tab)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘⌫").key, .delete)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘⎋").key, .escape)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘↑").key, .upArrow)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘→").key, .rightArrow)
    }

    func testParsePunctuationKeys() {
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘=").key, .equal)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘-").key, .minus)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘[").key, .leftBracket)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘/").key, .slash)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘.").key, .period)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘`").key, .grave)
    }

    func testParseDigitKeys() {
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘0").key, .zero)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘7").key, .seven)
    }

    func testParseInvalidStringYieldsNilKey() {
        let parsed = HotKeyManager.parseHotkeyString("NotAKey")
        XCTAssertNil(parsed.key)
    }

    func testParseEmptyStringYieldsNilKey() {
        let parsed = HotKeyManager.parseHotkeyString("")
        XCTAssertNil(parsed.key)
        XCTAssertTrue(parsed.modifiers.isEmpty)
    }

    func testParseModifiersOnlyYieldsNilKey() {
        let parsed = HotKeyManager.parseHotkeyString("⌘⇧")
        XCTAssertNil(parsed.key)
        XCTAssertTrue(parsed.modifiers.contains(.command))
        XCTAssertTrue(parsed.modifiers.contains(.shift))
    }

    func testParseIsCaseInsensitiveForLetters() {
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘a").key, .a)
        XCTAssertEqual(HotKeyManager.parseHotkeyString("⌘A").key, .a)
    }
}
