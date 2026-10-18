import SwiftUI

@MainActor
struct RebuildModePicker: View {
    let session: RebuildSession?
    @AppDefault(\.savedDictationModes) private var modes
    @AppDefault(\.currentDictationSettings) private var current
    @AppDefault(\.selectedDictationModeID) private var selectedID

    private var locked: Bool {
        guard let session else { return false }
        return session.phase.isBusy || session.isInstalling || session.maintenanceInProgress
    }

    var body: some View {
        Picker("Dictation mode", selection: Binding(
            get: { AppDefaults.activeDictationModeID?.uuidString ?? "" },
            set: { id in
                guard let mode = modes.first(where: { $0.id.uuidString == id }), !locked else { return }
                current = mode.settings
                selectedID = mode.id
                session?.selectionChanged()
            })) {
            Text("Custom settings").tag("").disabled(true)
            ForEach(modes) { Text($0.name).tag($0.id.uuidString) }
        }
        .disabled(modes.isEmpty || locked)
        .help("Switch the voice model, writing cleanup, vocabulary and formatting together.")
    }
}

@MainActor
struct RebuildSavedModesView: View {
    let session: RebuildSession?
    @AppDefault(\.savedDictationModes) private var modes
    @State private var name = ""
    @State private var message: String?

    private var locked: Bool {
        guard let session else { return false }
        return session.phase.isBusy || session.isInstalling || session.maintenanceInProgress
    }

    var body: some View {
        RebuildSection(title: "Dictation modes", caption: "Save a setup, then switch to it before your next recording.") {
            RebuildFormRow(label: "Use a mode") {
                RebuildModePicker(session: session).labelsHidden().frame(maxWidth: 360)
            }
            RebuildFormRow(label: "Save current setup") {
                HStack(spacing: 8) {
                    TextField("Mode name", text: $name).frame(maxWidth: 260)
                        .accessibilityLabel("New dictation mode name")
                        .onSubmit(save)
                    Button("Save mode", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Includes the voice model, cleanup model, vocabulary and formatting rules. "
                     + "Saved modes stay on this Mac. Set these options in Models & setup and Writing cleanup first.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message { RebuildCallout(tone: .error, message: message) }
            ForEach(modes) { mode in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name).font(.system(size: 12, weight: .medium))
                        Text(summary(mode.settings)).font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { modes.removeAll { $0.id == mode.id } }
                        .accessibilityLabel("Remove dictation mode \(mode.name)")
                }
            }
        }
        .disabled(locked)
    }

    private func save() {
        guard !locked else { return }
        do {
            let mode = try SavedDictationMode.make(name: name, settings: AppDefaults.currentDictationSettings, existing: modes)
            modes.append(mode)
            AppDefaults.selectedDictationModeID = mode.id
            name = ""
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func summary(_ settings: DictationModeSettings) -> String {
        let voice = settings.provider == .local ? "Whisper \(settings.whisper.rawValue)" : settings.parakeet.displayName
        return voice + (settings.cleanup == .off ? " · Cleanup off" : " · Local writing cleanup")
    }
}
