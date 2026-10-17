import Foundation

/// Edits individual entries without discarding comments or unrelated lines.
struct RebuildVocabularyDocument {
    struct Entry: Identifiable, Equatable {
        let id: Int
        let raw: String
        let heard: String?
        let written: String
        var title: String { heard ?? written }
        var detail: String {
            if heard == nil { return "Keep this spelling" }
            return written.isEmpty ? "Remove this phrase" : "Write as \(written)"
        }
    }

    struct Draft: Equatable {
        var entry: Entry?
        var replacement = false
        var heard = ""
        var written = ""

        init(entry: Entry? = nil) {
            self.entry = entry
            replacement = entry?.heard != nil
            heard = entry?.heard ?? ""
            written = entry?.written ?? ""
        }
    }

    enum EditError: LocalizedError {
        case empty, delimiter, duplicate, changed
        var errorDescription: String? {
            switch self {
            case .empty: return "Enter a word, or the phrase you want to replace."
            case .delimiter: return "Use one entry at a time, without arrows, line breaks or a leading #."
            case .duplicate: return "That entry already exists. Edit it in the list below."
            case .changed: return "This entry changed elsewhere. Open it again before saving."
            }
        }
    }

    let source: String
    private var lines: [String] { source.components(separatedBy: "\n") }
    var entries: [Entry] {
        lines.enumerated().compactMap { index, raw in
            let parsed = CustomVocabulary(parsing: raw)
            if let replacement = parsed.replacements.first {
                return Entry(id: index, raw: raw, heard: replacement.heard, written: replacement.written)
            }
            return parsed.terms.first.map { Entry(id: index, raw: raw, heard: nil, written: $0) }
        }
    }

    func matching(_ query: String) -> [Entry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle)
            || $0.written.localizedCaseInsensitiveContains(needle) }
    }

    func saving(_ draft: Draft) throws -> String {
        let heard = draft.heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = draft.written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(draft.replacement ? heard : written).isEmpty else { throw EditError.empty }
        for value in [heard, written] where !value.isEmpty {
            guard !value.contains(where: \.isNewline), !value.contains("->"), !value.contains("=>"), !value.hasPrefix("#")
            else { throw EditError.delimiter }
        }
        let key = draft.replacement ? heard : written
        guard !entries.contains(where: {
            $0.id != draft.entry?.id && ($0.heard != nil) == draft.replacement
                && $0.title.caseInsensitiveCompare(key) == .orderedSame
        }) else { throw EditError.duplicate }
        let line = draft.replacement ? "\(heard) -> \(written)" : written
        var updated = lines
        if let entry = draft.entry {
            guard updated.indices.contains(entry.id), updated[entry.id] == entry.raw else { throw EditError.changed }
            updated[entry.id] = line
        } else {
            if updated.last == "" { updated.removeLast() }
            updated.append(line)
        }
        return updated.joined(separator: "\n")
    }

    func removing(_ entry: Entry) throws -> String {
        var updated = lines
        guard updated.indices.contains(entry.id), updated[entry.id] == entry.raw else { throw EditError.changed }
        updated.remove(at: entry.id)
        return updated.joined(separator: "\n")
    }

    static func correction(from original: String, to edited: String) -> Draft {
        var draft = Draft()
        draft.replacement = true
        let before = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let after = edited.split(whereSeparator: \.isWhitespace).map(String.init)
        var start = 0
        while start < min(before.count, after.count), before[start] == after[start] { start += 1 }
        var endBefore = before.count
        var endAfter = after.count
        while endBefore > start, endAfter > start, before[endBefore - 1] == after[endAfter - 1] {
            endBefore -= 1
            endAfter -= 1
        }
        guard endBefore > start, endBefore - start <= 8, endAfter - start <= 8 else { return draft }
        var heard = before[start..<endBefore].joined(separator: " ")
        var written = after[start..<endAfter].joined(separator: " ")
        while heard.count > 1, written.count > 1, let last = heard.last,
              ".,!?;:…\"'“”‘’".contains(last), written.last == last {
            heard.removeLast()
            written.removeLast()
        }
        guard heard.count <= 120, written.count <= 120 else { return draft }
        draft.heard = heard
        draft.written = written
        return draft
    }
}
