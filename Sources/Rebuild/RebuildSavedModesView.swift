import SwiftUI

@MainActor
struct RebuildModePicker: View {
    let session: RebuildSession?
    @AppDefault(\.savedDictationModes) private var modes
    @AppDefault(\.currentDictationSettings) private var current
    @AppDefault(\.selectedDictationModeID) private var selectedID
    @AppDefault(\.automaticDictationModes) private var automatic

    private var locked: Bool {
        guard let session else { return false }
        return session.phase.isBusy || session.isInstalling || session.maintenanceInProgress
    }

    var body: some View {
        Picker("Dictation mode", selection: Binding(
            get: { AppDefaults.automaticDictationModes ? "automatic" : AppDefaults.activeDictationModeID?.uuidString ?? "" },
            set: { id in
                guard !locked else { return }
                automatic = id == "automatic"
                if automatic { return }
                if id.isEmpty { selectedID = nil; return }
                guard let mode = modes.first(where: { $0.id.uuidString == id }), !locked else { return }
                current = mode.settings
                selectedID = mode.id
                session?.selectionChanged()
            })) {
            Text("Automatic · App rules").tag("automatic")
            Text("Custom settings").tag("")
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
    @State private var editing: SavedDictationMode?

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
            HStack {
                Button("Import modes…") { importModes() }
                Button("Export all modes…") { RebuildModeFiles.export(modes) { message = $0 } }.disabled(modes.isEmpty)
            }
            ForEach(modes) { mode in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(mode.name).font(.system(size: 12, weight: .medium))
                        Text(summary(mode.settings)).font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                    }
                    Spacer()
                    Button("Edit…") { editing = mode }.accessibilityLabel("Edit dictation mode \(mode.name)")
                    Button("Duplicate") { duplicate(mode) }.accessibilityLabel("Duplicate dictation mode \(mode.name)")
                    Button("Remove", role: .destructive) {
                        modes.removeAll { $0.id == mode.id }
                        if AppDefaults.selectedDictationModeID == mode.id { AppDefaults.selectedDictationModeID = nil }
                    }
                        .accessibilityLabel("Remove dictation mode \(mode.name)")
                }
            }
        }
        .disabled(locked)
        .sheet(item: $editing) { mode in
            RebuildModeEditor(mode: mode) { updated in
                guard !locked, let index = modes.firstIndex(where: { $0.id == updated.id }) else {
                    throw RebuildModeFiles.ModeFileError.busy
                }
                let active = AppDefaults.activeDictationModeID == updated.id
                modes[index] = updated
                if active {
                    AppDefaults.currentDictationSettings = updated.settings
                    AppDefaults.selectedDictationModeID = updated.id
                    session?.selectionChanged()
                }
            }
        }
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

    private func duplicate(_ mode: SavedDictationMode) {
        guard !locked else { return }
        var suffix = 1
        var name = String(mode.name.prefix(45)) + " copy"
        while modes.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            suffix += 1
            name = String(mode.name.prefix(45)) + " copy \(suffix)"
        }
        do {
            modes.append(try SavedDictationMode.make(name: name, settings: mode.settings, existing: modes))
        } catch { message = error.localizedDescription }
    }

    private func importModes() {
        RebuildModeFiles.importModes { result in
            guard !locked else { message = RebuildModeFiles.ModeFileError.busy.localizedDescription; return }
            do {
                modes = try DictationModeArchive.importing(result.get(), into: modes)
                message = nil
            } catch { message = error.localizedDescription }
        }
    }
}
