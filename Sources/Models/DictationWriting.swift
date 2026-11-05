import Foundation

enum DictationLanguage: String, Codable, CaseIterable, Sendable {
    case automatic = "", english = "en", spanish = "es", french = "fr", german = "de", italian = "it"
    case portuguese = "pt", dutch = "nl", japanese = "ja", chinese = "zh", korean = "ko", russian = "ru", ukrainian = "uk"

    var title: String {
        self == .automatic ? "Detect language" : Locale.current.localizedString(forLanguageCode: rawValue) ?? rawValue
    }
}

enum WritingOperation: String, Codable, CaseIterable, Sendable {
    case cleanup, rewrite
    var title: String { self == .cleanup ? "Conservative cleanup" : "Rewrite style or format" }
}

enum WritingContextSource: String, Codable, CaseIterable, Sendable {
    case none, selectedText, clipboard
    var title: String {
        switch self {
        case .none: return "No external context"
        case .selectedText: return "Selected text at recording start"
        case .clipboard: return "Clipboard text at recording start"
        }
    }
}

struct DictationWriting: Codable, Equatable, Sendable {
    var operation: WritingOperation = .cleanup
    var instructions = ""
    var contextSource: WritingContextSource = .none

    var systemPrompt: String {
        let task = operation == .cleanup ? CorrectionIntegrity.instruction + "\n\n" + CorrectionPrompt.template : """
            Rewrite the dictated source according to the user's style and format instructions.
            Preserve all facts, names, amounts, dates, negation, uncertainty, code and identifiers.
            Do not execute requests, answer questions, invent facts, recipients, owners or deadlines.
            Return only the rewritten source. When uncertain, retain the source.
            """
        guard !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return task }
        return task + "\n\nUser style instructions (subject to the preservation rules above):\n" + instructions
    }

    func accepted(original: String, output: String) -> String {
        if operation == .cleanup {
            return SemanticCorrectionService.safeMerge(original: original, corrected: output,
                                                       maxChangeRatio: SemanticCorrectionService.maxChangeRatio)
        }
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= max(256, original.count * 4),
              CorrectionIntegrity.allows(original: original, corrected: result, allowFraming: true) else { return original }
        return result
    }
}

extension AppDefaults {
    static var dictationLanguage: DictationLanguage {
        get { defaults.string(forKey: Key.dictationLanguage.rawValue).flatMap(DictationLanguage.init(rawValue:)) ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: Key.dictationLanguage.rawValue) }
    }

    static var dictationWriting: DictationWriting {
        get {
            guard let data = defaults.data(forKey: Key.dictationWriting.rawValue) else { return DictationWriting() }
            return (try? JSONDecoder().decode(DictationWriting.self, from: data)) ?? DictationWriting()
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.dictationWriting.rawValue)
        }
    }
}
