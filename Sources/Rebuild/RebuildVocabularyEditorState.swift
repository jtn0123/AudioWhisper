import Foundation
import Observation

@MainActor
@Observable
final class RebuildVocabularyEditorState {
    var query = ""
    var draft = RebuildVocabularyDocument.Draft()
    var message: String?
    var isError = false
    private var removedSource: String?
    private var removedResult: String?
    var canUndo: Bool { removedSource != nil }

    func edit(_ entry: RebuildVocabularyDocument.Entry) { draft = .init(entry: entry); message = nil }
    func cancelEdit() { draft = .init(); message = nil }

    func save(in source: String) -> String? {
        do {
            let updated = try RebuildVocabularyDocument(source: source).saving(draft)
            message = draft.entry == nil ? "Entry added. Future recordings will use it." : "Entry updated."
            isError = false
            draft = .init()
            query = ""
            removedSource = nil
            removedResult = nil
            return updated
        } catch { return failed(error) }
    }

    func remove(_ entry: RebuildVocabularyDocument.Entry, in source: String) -> String? {
        do {
            let updated = try RebuildVocabularyDocument(source: source).removing(entry)
            removedSource = source
            removedResult = updated
            draft = .init()
            isError = false
            message = "Entry removed. You can undo this."
            return updated
        } catch { return failed(error) }
    }

    func undo(in source: String) -> String? {
        guard let removedSource else { return nil }
        guard source == removedResult else {
            isError = true
            message = "Vocabulary changed since removal. Undo would replace newer changes."
            return nil
        }
        self.removedSource = nil
        removedResult = nil
        message = "Entry restored."
        return removedSource
    }

    private func failed(_ error: Error) -> String? {
        isError = true
        message = error.localizedDescription
        return nil
    }
}
