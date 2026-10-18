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
    private var lines: [Substring] { source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) }
    var entries: [Entry] {
        lines.enumerated().compactMap { index, raw in
            let parsed = CustomVocabulary(parsing: String(raw))
            if let replacement = parsed.replacements.first {
                return Entry(id: index, raw: String(raw), heard: replacement.heard, written: replacement.written)
            }
            return parsed.terms.first.map { Entry(id: index, raw: String(raw), heard: nil, written: $0) }
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
        let key = draft.replacement ? heard : written
        guard !key.hasPrefix("#") else { throw EditError.delimiter }
        for value in draft.replacement ? [heard, written] : [written] {
            guard !value.contains(where: \.isNewline), !value.contains("->"), !value.contains("=>")
            else { throw EditError.delimiter }
        }
        guard !entries.contains(where: {
            $0.id != draft.entry?.id && ($0.heard != nil) == draft.replacement
                && $0.title.caseInsensitiveCompare(key) == .orderedSame
        }) else { throw EditError.duplicate }
        let line = draft.replacement ? "\(heard) -> \(written)" : written
        var updated = source
        if let entry = draft.entry {
            let current = try checkedLine(for: entry)
            updated.replaceSubrange(current.startIndex..<current.endIndex, with: line)
        } else {
            if !updated.isEmpty, updated.last?.isNewline != true { updated.append("\n") }
            updated.append(contentsOf: line)
        }
        return updated
    }

    func removing(_ entry: Entry) throws -> String {
        let current = try checkedLine(for: entry)
        let lines = lines
        let last = entry.id == lines.count - 1
        let start = last && entry.id > 0 ? lines[entry.id - 1].endIndex : current.startIndex
        let end = last ? current.endIndex : lines[entry.id + 1].startIndex
        var updated = source
        updated.removeSubrange(start..<end)
        return updated
    }

    private func checkedLine(for entry: Entry) throws -> Substring {
        let lines = lines
        guard lines.indices.contains(entry.id), lines[entry.id] == entry.raw else { throw EditError.changed }
        return lines[entry.id]
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
