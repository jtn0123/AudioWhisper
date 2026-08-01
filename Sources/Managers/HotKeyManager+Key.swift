import KeyboardShortcuts

// MARK: - Key Enum (drop-in replacement for HotKey.Key)
//
// We replaced the soffes/HotKey library with sindresorhus/KeyboardShortcuts.
// HotKey exposed a `Key` enum that several files (HotKeyRecorderView,
// DashboardRecordingView, tests) consume directly. To keep the public surface
// of those files unchanged, we re-publish the same enum here. It bridges to
// `KeyboardShortcuts.Key` via `keyboardShortcutsKey`.
//
// The single-character letter cases (`a`...`z`) intentionally mirror physical
// keyboard keys and are referenced verbatim by out-of-module callers
// (HotKeyRecorderView and its tests). Renaming them would break that public
// surface, so `identifier_name` is disabled for the case declarations only.
internal enum Key: Hashable {
    // swiftlint:disable identifier_name
    // Letters
    case a, b, c, d, e, f, g, h, i, j, k, l, m
    case n, o, p, q, r, s, t, u, v, w, x, y, z

    // Numbers (HotKey naming)
    case zero, one, two, three, four, five, six, seven, eight, nine

    // Function
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20

    // Punctuation / misc
    case `return`, tab, space, delete, escape
    case equal, minus, leftBracket, rightBracket, quote, semicolon
    case backslash, comma, slash, period, grave

    // Arrows
    case upArrow, downArrow, leftArrow, rightArrow
    // swiftlint:enable identifier_name

    /// Bridge to KeyboardShortcuts.Key.
    var keyboardShortcutsKey: KeyboardShortcuts.Key {
        if let letter = letterKey { return letter }
        if let digit = digitKey { return digit }
        if let function = functionKey { return function }
        return punctuationOrArrowKey
    }

    private var letterKey: KeyboardShortcuts.Key? {
        switch self {
        case .a: return .a
        case .b: return .b
        case .c: return .c
        case .d: return .d
        case .e: return .e
        case .f: return .f
        case .g: return .g
        case .h: return .h
        case .i: return .i
        case .j: return .j
        case .k: return .k
        case .l: return .l
        case .m: return .m
        case .n: return .n
        case .o: return .o
        case .p: return .p
        case .q: return .q
        case .r: return .r
        case .s: return .s
        case .t: return .t
        case .u: return .u
        case .v: return .v
        case .w: return .w
        case .x: return .x
        case .y: return .y
        case .z: return .z
        default: return nil
        }
    }

    private var digitKey: KeyboardShortcuts.Key? {
        switch self {
        case .zero: return .zero
        case .one: return .one
        case .two: return .two
        case .three: return .three
        case .four: return .four
        case .five: return .five
        case .six: return .six
        case .seven: return .seven
        case .eight: return .eight
        case .nine: return .nine
        default: return nil
        }
    }

    private var functionKey: KeyboardShortcuts.Key? {
        switch self {
        case .f1: return .f1
        case .f2: return .f2
        case .f3: return .f3
        case .f4: return .f4
        case .f5: return .f5
        case .f6: return .f6
        case .f7: return .f7
        case .f8: return .f8
        case .f9: return .f9
        case .f10: return .f10
        case .f11: return .f11
        case .f12: return .f12
        case .f13: return .f13
        case .f14: return .f14
        case .f15: return .f15
        case .f16: return .f16
        case .f17: return .f17
        case .f18: return .f18
        case .f19: return .f19
        case .f20: return .f20
        default: return nil
        }
    }

    private var punctuationOrArrowKey: KeyboardShortcuts.Key {
        switch self {
        case .return: return .return
        case .tab: return .tab
        case .space: return .space
        case .delete: return .delete
        case .escape: return .escape
        case .equal: return .equal
        case .minus: return .minus
        case .leftBracket: return .leftBracket
        case .rightBracket: return .rightBracket
        case .quote: return .quote
        case .semicolon: return .semicolon
        case .backslash: return .backslash
        case .comma: return .comma
        case .slash: return .slash
        case .period: return .period
        case .grave: return .backtick
        case .upArrow: return .upArrow
        case .downArrow: return .downArrow
        case .leftArrow: return .leftArrow
        case .rightArrow: return .rightArrow
        default: return .space
        }
    }
}
