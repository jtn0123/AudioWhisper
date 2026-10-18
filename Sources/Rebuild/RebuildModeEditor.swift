import SwiftUI

@MainActor
struct RebuildModeEditor: View {
    let mode: SavedDictationMode
    let save: (SavedDictationMode) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var settings: DictationModeSettings
    @State private var error: String?

    init(mode: SavedDictationMode, save: @escaping (SavedDictationMode) throws -> Void) {
        self.mode = mode
        self.save = save
        _name = State(initialValue: mode.name)
        _settings = State(initialValue: mode.settings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit dictation mode").font(.title2)
            ScrollView {
                Form {
                    TextField("Name", text: $name)
                    Picker("Voice engine", selection: $settings.provider) {
                        Text("Whisper").tag(TranscriptionProvider.local)
                        Text("Parakeet").tag(TranscriptionProvider.parakeet)
                    }
                    if settings.provider == .local {
                        Picker("Whisper model", selection: $settings.whisper) {
                            ForEach(WhisperModel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        Picker("Language", selection: $settings.language) {
                            ForEach(DictationLanguage.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    } else {
                        Picker("Parakeet model", selection: $settings.parakeet) {
                            ForEach(ParakeetModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        Text("Parakeet uses the selected model’s language support and automatic detection.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Picker("Writing cleanup", selection: $settings.cleanup) {
                        ForEach(SemanticCorrectionMode.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    TextField("Local cleanup model", text: $settings.cleanupModel)
                    Picker("Writing task", selection: $settings.writing.operation) {
                        ForEach(WritingOperation.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Style or formatting instructions", text: $settings.writing.instructions, axis: .vertical)
                        .lineLimit(3...8)
                    Text("Requires local writing cleanup. Originals remain available; "
                         + "names, numbers and literal code are checked.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Reference context", selection: $settings.writing.contextSource) {
                        ForEach(WritingContextSource.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Text("Opt in per mode. Read once before recording; used as local reference, never saved with history. "
                         + "This does not replace the selected text.").font(.caption).foregroundStyle(.secondary)
                    TextField("Vocabulary", text: $settings.vocabulary, axis: .vertical).lineLimit(3...8)
                    Toggle("Remove filler words", isOn: $settings.removeFillers)
                    Toggle("Spoken punctuation", isOn: $settings.spokenPunctuation)
                }.formStyle(.grouped)
            }
            if let error { RebuildCallout(tone: .error, message: error) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save changes", action: commit).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600, height: 690)
    }

    private func commit() {
        guard settings.writing.instructions.count <= 4_000, settings.vocabulary.count <= 32_000,
              !settings.cleanupModel.isEmpty, settings.cleanupModel.count <= 200 else {
            error = "Keep instructions under 4,000 characters, vocabulary under 32,000, and a valid local model name."
            return
        }
        do {
            try save(mode.updated(name: name, settings: settings, existing: AppDefaults.savedDictationModes))
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
