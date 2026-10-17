import SwiftUI

struct RebuildVocabularyEditor: View {
    @AppDefault(\.customVocabulary) private var vocabulary
    @State private var state: RebuildVocabularyEditorState
    @FocusState private var searchFocused: Bool

    private var document: RebuildVocabularyDocument { .init(source: vocabulary) }

    @MainActor
    init(state: RebuildVocabularyEditorState? = nil) { _state = State(initialValue: state ?? .init()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Vocabulary").font(.system(size: 12.5, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Text(RebuildWritingRulesCard.summary(of: CustomVocabulary(parsing: vocabulary)))
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            }
            Text("Keep names spelled correctly, or replace something you often say. Changes apply to future recordings.")
                .font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText)
            HStack {
                TextField("Search words or replacements", text: $state.query).textFieldStyle(.roundedBorder)
                    .focused($searchFocused).accessibilityLabel("Search vocabulary")
                    .onExitCommand { state.query = "" }
                Button("Search vocabulary", systemImage: "magnifyingglass") { searchFocused = true }
                    .labelStyle(.iconOnly).keyboardShortcut("f").help("Search vocabulary (Command F)")
            }
            entries
            Divider()
            RebuildVocabularyFields(draft: $state.draft).onSubmit(save)
            HStack {
                Button(state.draft.entry == nil ? "Add entry" : "Save changes", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                if state.draft.entry != nil { Button("Cancel edit", action: state.cancelEdit) }
                Spacer()
                if state.canUndo {
                    Button("Undo remove") { if let updated = state.undo(in: vocabulary) { vocabulary = updated } }
                }
            }
            if let message = state.message {
                RebuildCallout(tone: state.isError ? .error : .success, message: message)
                    .rebuildAnnouncement(message, onAppear: true)
            }
        }
    }

    @ViewBuilder private var entries: some View {
        let matches = document.matching(state.query)
        if matches.isEmpty {
            Text(state.query.isEmpty
                ? "No words yet. Add a name or replacement below." : "No matching entries. Try another search.")
                .font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText).padding(.vertical, 8)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(matches) { entry in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title).font(.system(size: 12.5, weight: .medium)).textSelection(.enabled)
                                Text(entry.detail).font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Button("Edit \(entry.title)", systemImage: "pencil") { state.edit(entry) }
                                .labelStyle(.iconOnly).help("Edit \(entry.title)")
                            Button("Remove \(entry.title)", systemImage: "minus.circle", role: .destructive) { remove(entry) }
                                .labelStyle(.iconOnly).help("Remove \(entry.title)")
                        }.padding(.vertical, 8)
                        Divider()
                    }
                }
            }.frame(height: min(CGFloat(matches.count) * 55, 220))
                .accessibilityLabel("Vocabulary entries")
        }
    }

    private func save() {
        if let updated = state.save(in: vocabulary) { vocabulary = updated }
    }

    private func remove(_ entry: RebuildVocabularyDocument.Entry) {
        if let updated = state.remove(entry, in: vocabulary) { vocabulary = updated }
    }
}

struct RebuildVocabularyFields: View {
    @Binding var draft: RebuildVocabularyDocument.Draft
    var focusOnAppear = false
    private enum Field { case heard, written }
    @FocusState private var focused: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Entry type", selection: $draft.replacement) {
                Text("Word or name").tag(false)
                Text("Replacement").tag(true)
            }.pickerStyle(.segmented).fixedSize()
            if draft.replacement {
                TextField("Heard phrase", text: $draft.heard).textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .heard)
                    .accessibilityLabel("Heard phrase")
            }
            TextField(
                draft.replacement ? "Write as (leave empty to remove the phrase)" : "Correct spelling", text: $draft.written)
                .textFieldStyle(.roundedBorder).accessibilityLabel(draft.replacement ? "Write as" : "Correct spelling")
                .focused($focused, equals: .written)
        }
        .onAppear { if focusOnAppear { focusFirstField() } }
        .onChange(of: draft.replacement) { _, _ in focusFirstField() }
        .onChange(of: draft.entry?.id) { _, _ in focusFirstField() }
    }

    private func focusFirstField() { focused = draft.replacement ? .heard : .written }
}

struct RebuildRememberCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppDefault(\.customVocabulary) private var vocabulary
    @State var draft: RebuildVocabularyDocument.Draft
    @State private var error: String?
    var saved: () -> Void = {
        // Standalone sheets save and dismiss without a parent success indicator to update.
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Remember a correction").font(.title3.weight(.semibold))
            Text("Save a phrase you corrected so future recordings use the right words.")
                .font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText)
            RebuildVocabularyFields(draft: $draft, focusOnAppear: true)
            if let error { RebuildCallout(tone: .error, message: error) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save correction") {
                    do {
                        vocabulary = try RebuildVocabularyDocument(source: vocabulary).saving(draft)
                        saved()
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 440)
    }
}
