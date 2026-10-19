import SwiftUI
import Observation

@MainActor
struct RebuildModeEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RebuildModeDraft

    init(mode: SavedDictationMode, save: @escaping (SavedDictationMode) throws -> Void) {
        _draft = State(initialValue: RebuildModeDraft(mode: mode, save: save))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit dictation mode").font(.title2)
            ScrollView {
                Form {
                    TextField("Name", text: $draft.name)
                    Picker("Voice engine", selection: $draft.settings.provider) {
                        Text("Whisper").tag(TranscriptionProvider.local)
                        Text("Parakeet").tag(TranscriptionProvider.parakeet)
                    }
                    if draft.settings.provider == .local {
                        Picker("Whisper model", selection: $draft.settings.whisper) {
                            ForEach(WhisperModel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Language", selection: $draft.settings.language) {
                            ForEach(DictationLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    } else {
                        Picker("Parakeet model", selection: $draft.settings.parakeet) {
                            ForEach(ParakeetModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        Text("Parakeet uses the selected model’s language support and automatic detection.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Writing cleanup", selection: $draft.settings.cleanup) {
                        ForEach(SemanticCorrectionMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField("Local cleanup model", text: $draft.settings.cleanupModel)
                    Picker("Writing task", selection: $draft.settings.writing.operation) {
                        ForEach(WritingOperation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Style or formatting instructions", text: $draft.settings.writing.instructions, axis: .vertical)
                        .lineLimit(3...8)
                    Text("Requires local writing cleanup. Originals remain available; "
                         + "names, numbers and literal code are checked.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Reference context", selection: $draft.settings.writing.contextSource) {
                        ForEach(WritingContextSource.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Opt in per mode. Read once before recording; used as local reference, never saved with history. "
                         + "Selected-text reference uses copy-only delivery. Review the result before pasting it.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Vocabulary", text: $draft.settings.vocabulary, axis: .vertical).lineLimit(3...8)
                    Toggle("Remove filler words", isOn: $draft.settings.removeFillers)
                    Toggle("Spoken punctuation", isOn: $draft.settings.spokenPunctuation)
                }.formStyle(.grouped)
            }
            if let error = draft.error { RebuildCallout(tone: .error, message: error) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save changes", action: commit).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600, height: 690)
    }

    private func commit() {
        if draft.commit() { dismiss() }
    }
}

@MainActor
@Observable
final class RebuildModeDraft {
    let mode: SavedDictationMode
    var name: String
    var settings: DictationModeSettings
    private(set) var error: String?
    private let save: (SavedDictationMode) throws -> Void

    init(mode: SavedDictationMode, save: @escaping (SavedDictationMode) throws -> Void) {
        self.mode = mode
        name = mode.name
        settings = mode.settings
        self.save = save
    }

    func commit() -> Bool {
        guard settings.writing.instructions.count <= 4_000, settings.vocabulary.count <= 32_000,
              !settings.cleanupModel.isEmpty, settings.cleanupModel.count <= 200 else {
            error = "Keep instructions under 4,000 characters, vocabulary under 32,000, and a valid local model name."
            return false
        }
        do {
            try save(mode.updated(name: name, settings: settings, existing: AppDefaults.savedDictationModes))
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
}
