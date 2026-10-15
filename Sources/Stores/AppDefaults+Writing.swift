import Foundation

// MARK: - Writing Settings

extension AppDefaults {
    /// The user's vocabulary as typed: one term or `heard -> written` per line.
    /// Parsed by `CustomVocabulary(parsing:)`.
    static var customVocabulary: String {
        get { defaults.string(forKey: Key.customVocabulary.rawValue) ?? "" }
        set { defaults.set(newValue, forKey: Key.customVocabulary.rawValue) }
    }

    /// Drops "uh", "uhm" and interjection "um". On by default: the rules only
    /// touch sounds that are never words, so the change is safe to make silently.
    static var removeFillerWords: Bool {
        get { bool(.removeFillerWords, default: true) }
        set { defaults.set(newValue, forKey: Key.removeFillerWords.rawValue) }
    }

    /// Turns "comma", "period", "new line"… into punctuation. Off by default:
    /// someone who has not asked for it may mean the word.
    static var spokenPunctuation: Bool {
        get { bool(.spokenPunctuation, default: false) }
        set { defaults.set(newValue, forKey: Key.spokenPunctuation.rawValue) }
    }

    /// Fits Smart Paste output to the text before the cursor.
    static var matchCursorContext: Bool {
        get { bool(.matchCursorContext, default: true) }
        set { defaults.set(newValue, forKey: Key.matchCursorContext.rawValue) }
    }

    /// After Smart Paste, puts back what was on the clipboard before. Off by
    /// default: the transcript staying on the clipboard is the long-standing
    /// promise, and a fallback for pasting by hand.
    static var restoreClipboardAfterPaste: Bool {
        get { bool(.restoreClipboardAfterPaste, default: false) }
        set { defaults.set(newValue, forKey: Key.restoreClipboardAfterPaste.rawValue) }
    }

    private static func bool(_ key: Key, default fallback: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) == nil ? fallback : defaults.bool(forKey: key.rawValue)
    }
}
