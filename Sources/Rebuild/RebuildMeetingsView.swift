import AppKit
import SwiftUI

@MainActor
struct RebuildMeetingsView: View {
    @Bindable var state: RebuildMeetingSession
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                captureCard
                processingCard
                if !state.progress.isEmpty {
                    Text(state.progress).font(.callout).rebuildAnnouncement(state.progress)
                }
                if let error = state.error { RebuildCallout(tone: .error, message: error) }
                if let document = state.document { documentCard(document) }
                savedMeetings
            }.padding(.horizontal, 28).padding(.vertical, 20)
                .frame(maxWidth: 860, alignment: .leading)
        }
        .task { state.refresh() }
        .confirmationDialog("Delete this meeting, transcript, notes and source audio permanently?", isPresented: $confirmDelete) {
            Button("Delete meeting", role: .destructive) { state.deleteCurrent() }
        }
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture a meeting").font(.headline)
            TextField("Meeting title", text: $state.title).disabled(state.busy)
            HStack {
                Toggle("Default microphone", isOn: $state.microphone)
                Toggle("System audio", isOn: $state.systemAudio)
            }.disabled(state.busy)
            Text("Up to 30 minutes. System audio requires Screen & System Audio Recording permission; "
                 + "no screen images are saved. Use headphones to keep system playback out of the microphone track.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start meeting") { state.start() }.disabled(!state.canStart).buttonStyle(.borderedProminent)
                if state.activity == .starting || state.activity == .capturing {
                    Button("Stop & keep audio") { Task { await state.stop() } }
                }
                if state.activity == .starting || state.activity == .stopping { ProgressView().controlSize(.small) }
            }
        }.rebuildCard(padding: 18)
    }

    private var processingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local processing").font(.headline)
            Picker("Whisper model", selection: $state.voiceModel) {
                ForEach(WhisperModel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.disabled(state.busy)
            Text("Uses an already installed Whisper model. Language follows your dictation settings. "
                 + "Microphone and system tracks retain their own timestamps and source labels.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Choose local speaker models…", action: chooseSpeakerModels)
                if state.speakerModelFolder != nil {
                    Text("Speaker clustering enabled").font(.caption)
                    Button("Turn off") { state.speakerModelFolder = nil }
                }
            }.disabled(state.busy)
            Text("Optional SpeakerKit models must already be on this Mac. Cluster labels are estimates within each source track, "
                 + "not identities or cross-track speaker matches.").font(.caption).foregroundStyle(.secondary)
            Toggle("Generate local meeting notes", isOn: $state.makeSummary).disabled(state.busy)
            if state.makeSummary {
                Text("Uses your installed writing model: \(AppDefaults.semanticCorrectionModelRepo). "
                     + "Review decisions, owners and dates against the transcript.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Keep source audio after successful processing", isOn: $state.keepAudio).disabled(state.busy)
            Text("Audio is always retained on interruption or processing failure. "
                 + "On success it is deleted unless Keep source audio is selected. "
                 + "Transcripts and notes stay until you delete the meeting.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Process captured audio") { state.processCurrent() }
                    .disabled(state.busy || state.document?.audioRetained != true || state.document?.chunks.isEmpty != false)
                if state.activity == .processing {
                    ProgressView().controlSize(.small)
                    Button("Cancel processing") { state.cancelProcessing() }
                }
            }
        }.rebuildCard(padding: 18)
            .disabled(state.busy && state.activity != .processing)
    }

    private func documentCard(_ document: MeetingDocument) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(document.title).font(.headline)
                Spacer()
                Text(document.status.rawValue.capitalized).font(.caption)
            }
            Text(document.startedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
            Text(document.audioRetained ? "Source audio retained on this Mac" : "Source audio deleted after processing")
                .font(.caption).foregroundStyle(.secondary)
            if let note = document.note { RebuildCallout(tone: .warning, message: note) }
            if let summary = document.summary {
                DisclosureGroup("Meeting notes · review required") { Text(summary).textSelection(.enabled) }
            }
            if !document.segments.isEmpty {
                DisclosureGroup("Transcript · \(document.segments.count) timestamped segments") {
                    Text(document.transcript).font(.system(size: 12.5)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack {
                    Button("Copy transcript") { PasteManager.copyToClipboard(document.transcript) }
                    Button("Export transcript…") { export(document) }
                }
            }
            Button("Delete meeting…", role: .destructive) { confirmDelete = true }.disabled(state.busy)
        }.rebuildCard(padding: 18)
    }

    private var savedMeetings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved meetings").font(.headline)
            if let notice = state.inventoryNotice { RebuildCallout(tone: .warning, message: notice) }
            if state.documents.isEmpty { Text("Your captured meetings will appear here.").foregroundStyle(.secondary) }
            ForEach(state.documents) { document in
                Button { state.open(document.id) } label: {
                    HStack {
                        Text(document.title)
                        Spacer()
                        Text(document.startedAt, format: .dateTime.month().day().hour().minute())
                    }.frame(maxWidth: .infinity)
                }.disabled(state.busy)
            }
        }.rebuildCard(padding: 18)
    }

    private func chooseSpeakerModels() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, !state.busy else { return }
            state.speakerModelFolder = panel.url?.path
        }
    }

    private func export(_ document: MeetingDocument) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Meeting transcript.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = document.title + "\n\n" + (document.summary.map { $0 + "\n\n" } ?? "") + document.transcript
            do { try Data(text.utf8).write(to: url, options: .atomic) } catch { state.error = error.localizedDescription }
        }
    }
}
