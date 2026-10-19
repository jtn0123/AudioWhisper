import SwiftUI

@MainActor
struct RebuildHistoryCleanupView: View {
    @State var state: RebuildHistoryCleanup
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run writing cleanup").font(.title2)
            Text("Uses the stored original, without recognizing audio again or reading external context. "
                 + "Your original stays unchanged. The ten latest saved versions are kept with it.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Writing mode", selection: $state.selectedMode) {
                Text("Current settings").tag("current")
                ForEach(AppDefaults.savedDictationModes) { Text($0.name).tag($0.id.uuidString) }
            }.disabled(state.running)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Stored original").font(.headline)
                    Text(state.original).textSelection(.enabled)
                    if let result = state.result {
                        Divider()
                        Text("New version · \(state.saved ? "Saved" : "Preview")").font(.headline)
                        Text(result).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.rebuildCard(padding: 14)
            if let error = state.error { RebuildCallout(tone: .error, message: error) }
            HStack {
                Button("Close") { state.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                if state.running { ProgressView().controlSize(.small) }
                Spacer()
                Button("Run cleanup") { state.run() }.disabled(state.blocked)
                if let result = state.result {
                    Button("Copy result") { PasteManager.copyToClipboard(result) }
                    Button(state.saved ? "Version saved" : "Save version") { Task { await state.save() } }
                        .disabled(state.saved || state.running)
                }
            }
        }.padding(24).frame(width: 700, height: 600)
            .onDisappear { state.cancel() }
    }
}
