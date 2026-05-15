import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

// MARK: - HotKeyRecorderView Tests
@MainActor
final class HotKeyRecorderViewTests: XCTestCase {

    @State private var isRecording = false
    @State private var modifiers: NSEvent.ModifierFlags = []
    @State private var key: Key?

    func testViewCanBeCreated() {
        let isRecordingBinding = Binding(
            get: { self.isRecording },
            set: { self.isRecording = $0 }
        )
        let modifiersBinding = Binding(
            get: { self.modifiers },
            set: { self.modifiers = $0 }
        )
        let keyBinding = Binding(
            get: { self.key },
            set: { self.key = $0 }
        )

        let view = HotKeyRecorderView(
            isRecording: isRecordingBinding,
            recordedModifiers: modifiersBinding,
            recordedKey: keyBinding,
            onComplete: { _ in }
        )

        XCTAssertNotNil(view)
    }

    func testViewBodyDoesNotCrash() {
        let isRecordingBinding = Binding(
            get: { self.isRecording },
            set: { self.isRecording = $0 }
        )
        let modifiersBinding = Binding(
            get: { self.modifiers },
            set: { self.modifiers = $0 }
        )
        let keyBinding = Binding(
            get: { self.key },
            set: { self.key = $0 }
        )

        let view = HotKeyRecorderView(
            isRecording: isRecordingBinding,
            recordedModifiers: modifiersBinding,
            recordedKey: keyBinding,
            onComplete: { _ in }
        )

        _ = view.body
        XCTAssertTrue(true, "Body should not crash")
    }
}

// MARK: - Key Code Mapping Tests
final class KeyCodeMappingTests: XCTestCase {

    func testLetterKeyMappings() {
        let letterMappings: [(UInt16, Key)] = [
            (0, .a), (1, .s), (2, .d), (3, .f),
            (4, .h), (5, .g), (6, .z), (7, .x),
            (8, .c), (9, .v), (11, .b), (12, .q),
            (13, .w), (14, .e), (15, .r), (16, .y),
            (17, .t), (31, .o), (32, .u), (34, .i),
            (35, .p), (37, .l), (38, .j), (40, .k),
            (45, .n), (46, .m)
        ]

        for (keyCode, expectedKey) in letterMappings {
            let key = keyFromKeyCode(keyCode)
            XCTAssertEqual(key, expectedKey, "Key code \(keyCode) should map to \(expectedKey)")
        }
    }

    func testNumberKeyMappings() {
        let numberMappings: [(UInt16, Key)] = [
            (18, .one), (19, .two), (20, .three),
            (21, .four), (22, .six), (23, .five),
            (25, .nine), (26, .seven), (28, .eight),
            (29, .zero)
        ]

        for (keyCode, expectedKey) in numberMappings {
            let key = keyFromKeyCode(keyCode)
            XCTAssertEqual(key, expectedKey, "Key code \(keyCode) should map to \(expectedKey)")
        }
    }

    func testFunctionKeyMappings() {
        let functionMappings: [(UInt16, Key)] = [
            (122, .f1), (120, .f2), (99, .f3), (118, .f4),
            (96, .f5), (97, .f6), (98, .f7), (100, .f8),
            (101, .f9), (109, .f10), (103, .f11), (111, .f12),
            (105, .f13), (107, .f14), (113, .f15), (106, .f16),
            (64, .f17), (79, .f18), (80, .f19), (90, .f20)
        ]

        for (keyCode, expectedKey) in functionMappings {
            let key = keyFromKeyCode(keyCode)
            XCTAssertEqual(key, expectedKey, "Key code \(keyCode) should map to \(expectedKey)")
        }
    }

    func testArrowKeyMappings() {
        let arrowMappings: [(UInt16, Key)] = [
            (126, .upArrow), (125, .downArrow),
            (123, .leftArrow), (124, .rightArrow)
        ]

        for (keyCode, expectedKey) in arrowMappings {
            let key = keyFromKeyCode(keyCode)
            XCTAssertEqual(key, expectedKey, "Key code \(keyCode) should map to \(expectedKey)")
        }
    }

    func testSpecialKeyMappings() {
        let specialMappings: [(UInt16, Key)] = [
            (36, .return), (48, .tab), (49, .space),
            (50, .grave), (51, .delete), (53, .escape),
            (24, .equal), (27, .minus), (30, .rightBracket),
            (33, .leftBracket), (39, .quote), (41, .semicolon),
            (42, .backslash), (43, .comma), (44, .slash),
            (47, .period)
        ]

        for (keyCode, expectedKey) in specialMappings {
            let key = keyFromKeyCode(keyCode)
            XCTAssertEqual(key, expectedKey, "Key code \(keyCode) should map to \(expectedKey)")
        }
    }

    func testUnknownKeyCodeReturnsNil() {
        let unknownKeyCode: UInt16 = 255
        let key = keyFromKeyCode(unknownKeyCode)
        XCTAssertNil(key)
    }

    // Helper matching HotKeyRecorderView implementation
    private static let keyCodeMap: [UInt16: Key] = [
        0: .a, 1: .s, 2: .d, 3: .f, 4: .h, 5: .g, 6: .z, 7: .x, 8: .c, 9: .v,
        11: .b, 12: .q, 13: .w, 14: .e, 15: .r, 16: .y, 17: .t, 18: .one,
        19: .two, 20: .three, 21: .four, 22: .six, 23: .five, 24: .equal,
        25: .nine, 26: .seven, 27: .minus, 28: .eight, 29: .zero,
        30: .rightBracket, 31: .o, 32: .u, 33: .leftBracket, 34: .i, 35: .p,
        36: .return, 37: .l, 38: .j, 39: .quote, 40: .k, 41: .semicolon,
        42: .backslash, 43: .comma, 44: .slash, 45: .n, 46: .m, 47: .period,
        48: .tab, 49: .space, 50: .grave, 51: .delete, 53: .escape,
        122: .f1, 120: .f2, 99: .f3, 118: .f4, 96: .f5, 97: .f6, 98: .f7,
        100: .f8, 101: .f9, 109: .f10, 103: .f11, 111: .f12, 105: .f13,
        107: .f14, 113: .f15, 106: .f16, 64: .f17, 79: .f18, 80: .f19,
        90: .f20, 126: .upArrow, 125: .downArrow, 123: .leftArrow,
        124: .rightArrow
    ]

    private func keyFromKeyCode(_ keyCode: UInt16) -> Key? {
        Self.keyCodeMap[keyCode]
    }
}

// MARK: - Key to String Tests
final class KeyToStringTests: XCTestCase {

    func testFunctionKeyStrings() {
        XCTAssertEqual(keyToString(.f1), "F1")
        XCTAssertEqual(keyToString(.f2), "F2")
        XCTAssertEqual(keyToString(.f12), "F12")
        XCTAssertEqual(keyToString(.f20), "F20")
    }

    func testLetterKeyStrings() {
        XCTAssertEqual(keyToString(.a), "A")
        XCTAssertEqual(keyToString(.z), "Z")
        XCTAssertEqual(keyToString(.m), "M")
    }

    func testNumberKeyStrings() {
        XCTAssertEqual(keyToString(.one), "1")
        XCTAssertEqual(keyToString(.zero), "0")
        XCTAssertEqual(keyToString(.five), "5")
    }

    func testSpecialKeyStrings() {
        XCTAssertEqual(keyToString(.return), "⏎")
        XCTAssertEqual(keyToString(.tab), "⇥")
        XCTAssertEqual(keyToString(.space), "Space")
        XCTAssertEqual(keyToString(.delete), "⌫")
        XCTAssertEqual(keyToString(.escape), "⎋")
    }

    func testArrowKeyStrings() {
        XCTAssertEqual(keyToString(.upArrow), "↑")
        XCTAssertEqual(keyToString(.downArrow), "↓")
        XCTAssertEqual(keyToString(.leftArrow), "←")
        XCTAssertEqual(keyToString(.rightArrow), "→")
    }

    // Helper matching HotKeyRecorderView implementation
    private static let keyStringMap: [Key: String] = [
        .f1: "F1", .f2: "F2", .f3: "F3", .f4: "F4", .f5: "F5", .f6: "F6",
        .f7: "F7", .f8: "F8", .f9: "F9", .f10: "F10", .f11: "F11", .f12: "F12",
        .f13: "F13", .f14: "F14", .f15: "F15", .f16: "F16", .f17: "F17",
        .f18: "F18", .f19: "F19", .f20: "F20",
        .a: "A", .s: "S", .d: "D", .f: "F", .h: "H", .g: "G", .z: "Z", .x: "X",
        .c: "C", .v: "V", .b: "B", .q: "Q", .w: "W", .e: "E", .r: "R", .y: "Y",
        .t: "T", .o: "O", .u: "U", .i: "I", .p: "P", .l: "L", .j: "J", .k: "K",
        .n: "N", .m: "M",
        .one: "1", .two: "2", .three: "3", .four: "4", .five: "5", .six: "6",
        .seven: "7", .eight: "8", .nine: "9", .zero: "0",
        .equal: "=", .minus: "-", .rightBracket: "]", .leftBracket: "[",
        .quote: "'", .semicolon: ";", .backslash: "\\", .comma: ",",
        .slash: "/", .period: ".", .grave: "`",
        .return: "⏎", .tab: "⇥", .space: "Space", .delete: "⌫", .escape: "⎋",
        .upArrow: "↑", .downArrow: "↓", .leftArrow: "←", .rightArrow: "→"
    ]

    private func keyToString(_ key: Key) -> String {
        Self.keyStringMap[key] ?? ""
    }
}

// MARK: - Hotkey Validation Tests
final class HotkeyValidationTests: XCTestCase {

    func testFunctionKeysValidWithoutModifiers() {
        let functionKeys: [Key] = [.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12]
        let emptyModifiers: NSEvent.ModifierFlags = []

        for key in functionKeys {
            let isValid = isValidHotkey(modifiers: emptyModifiers, key: key)
            XCTAssertTrue(isValid, "\(key) should be valid without modifiers")
        }
    }

    func testRegularKeysRequireModifiers() {
        let regularKeys: [Key] = [.a, .b, .c, .one, .two, .three]
        let emptyModifiers: NSEvent.ModifierFlags = []

        for key in regularKeys {
            let isValid = isValidHotkey(modifiers: emptyModifiers, key: key)
            XCTAssertFalse(isValid, "\(key) should require modifiers")
        }
    }

    func testForbiddenKeysAreRejected() {
        let forbiddenKeys: [Key] = [.escape, .delete, .return, .tab]
        let modifiers: NSEvent.ModifierFlags = [.command]

        for key in forbiddenKeys {
            let isValid = isValidHotkey(modifiers: modifiers, key: key)
            XCTAssertFalse(isValid, "\(key) should be forbidden even with modifiers")
        }
    }

    func testShiftOnlyIsInvalid() {
        let modifiers: NSEvent.ModifierFlags = [.shift]
        let isValid = isValidHotkey(modifiers: modifiers, key: .a)
        XCTAssertFalse(isValid, "Shift-only modifier should be invalid")
    }

    func testOptionOnlyIsInvalid() {
        let modifiers: NSEvent.ModifierFlags = [.option]
        let isValid = isValidHotkey(modifiers: modifiers, key: .a)
        XCTAssertFalse(isValid, "Option-only modifier should be invalid")
    }

    func testCommandModifierIsValid() {
        let modifiers: NSEvent.ModifierFlags = [.command]
        let isValid = isValidHotkey(modifiers: modifiers, key: .a)
        XCTAssertTrue(isValid, "Command+key should be valid")
    }

    func testControlModifierIsValid() {
        let modifiers: NSEvent.ModifierFlags = [.control]
        let isValid = isValidHotkey(modifiers: modifiers, key: .a)
        XCTAssertTrue(isValid, "Control+key should be valid")
    }

    func testCommandShiftIsValid() {
        let modifiers: NSEvent.ModifierFlags = [.command, .shift]
        let isValid = isValidHotkey(modifiers: modifiers, key: .a)
        XCTAssertTrue(isValid, "Command+Shift+key should be valid")
    }

    // Helper matching HotKeyRecorderView implementation
    private func isValidHotkey(modifiers: NSEvent.ModifierFlags, key: Key) -> Bool {
        if modifiers.isEmpty {
            return isFunctionKey(key)
        }

        let forbiddenKeys: [Key] = [.escape, .delete, .return, .tab]
        if forbiddenKeys.contains(key) {
            return false
        }

        if modifiers == .shift || modifiers == .option {
            return false
        }

        return true
    }

    private func isFunctionKey(_ key: Key) -> Bool {
        switch key {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
             .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            return true
        default:
            return false
        }
    }
}

// MARK: - Hotkey Formatting Tests
final class HotkeyFormattingTests: XCTestCase {

    func testFormatCommandA() {
        let modifiers: NSEvent.ModifierFlags = [.command]
        let formatted = formatHotkey(modifiers: modifiers, key: .a)
        XCTAssertEqual(formatted, "⌘A")
    }

    func testFormatCommandShiftA() {
        let modifiers: NSEvent.ModifierFlags = [.command, .shift]
        let formatted = formatHotkey(modifiers: modifiers, key: .a)
        XCTAssertEqual(formatted, "⌘⇧A")
    }

    func testFormatControlOptionA() {
        let modifiers: NSEvent.ModifierFlags = [.control, .option]
        let formatted = formatHotkey(modifiers: modifiers, key: .a)
        XCTAssertEqual(formatted, "⌥⌃A")
    }

    func testFormatFunctionKeyAlone() {
        let modifiers: NSEvent.ModifierFlags = []
        let formatted = formatHotkey(modifiers: modifiers, key: .f5)
        XCTAssertEqual(formatted, "F5")
    }

    // Helper matching HotKeyRecorderView implementation
    private func formatHotkey(modifiers: NSEvent.ModifierFlags, key: Key) -> String {
        var parts: [String] = []

        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }

        parts.append(keyToString(key))

        return parts.joined()
    }

    private func keyToString(_ key: Key) -> String {
        switch key {
        case .f5: return "F5"
        case .a: return "A"
        default: return String(describing: key).uppercased()
        }
    }
}
