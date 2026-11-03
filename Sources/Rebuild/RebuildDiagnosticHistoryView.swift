import SwiftUI

@MainActor
struct RebuildDiagnosticHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("diagnostics.historyEnabled", store: AppDefaults.defaults) private var enabled = true
    @AppStorage("diagnostics.resourceSampling", store: AppDefaults.defaults) private var detailed = false
    @State private var state: RebuildDiagnosticHistoryState
    @State private var confirmClear = false

    init(state: RebuildDiagnosticHistoryState? = nil) {
        _state = State(initialValue: state ?? RebuildDiagnosticHistoryState())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Local diagnostics").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Timings and technical metadata stay on this Mac. No audio, transcripts, prompts, selected text, "
                 + "clipboard contents or window titles are included. Export only when you choose to share a file.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Keep recent diagnostic history", isOn: $enabled)
            Toggle("Sample application CPU and memory every second during sessions", isOn: $detailed).disabled(!enabled)
            Text("Keeps up to 100 sessions and 100 window events for 7 days, within a 2 MB file. "
                 + "Turning history off stops future collection. Clear removes existing diagnostics.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            let summary = DiagnosticSummary(state.archive.sessions)
            Text("\(summary.count) sessions · \(summary.failures) failed · \(state.archive.windows.count) window events")
            if state.storageFailed {
                Text("Diagnostic storage could not be read or written. Recording is unaffected. "
                     + "The existing file is preserved; clear it to start a new history.").foregroundStyle(.orange)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Completed stage timings · milliseconds").font(.headline)
                    Text("Median and p95 use nearest rank from this small local sample. Stages can overlap; do not add them. "
                         + "Worker operations include model loading. "
                         + "Stop to delivery excludes clipboard restoration and history saving.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(DiagnosticStage.allCases, id: \.self) { stage in
                        if let value = summary.stages[stage] {
                            HStack {
                                Text(stage.label)
                                Spacer()
                                Text("median \(value.median, specifier: "%.0f") · p95 \(value.p95, specifier: "%.0f")")
                                    .monospacedDigit()
                            }.font(.callout)
                        }
                    }
                    Text("Application samples: cumulative process CPU and current resident memory. "
                         + "Model worker: CPU used by each operation and process lifetime peak resident memory. "
                         + "These are separate processes; memory is not GPU allocation or a system-wide total.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(minHeight: 160, maxHeight: 280)
            if let message = state.message { Text(message).font(.callout).textSelection(.enabled) }
            HStack {
                Button("Export diagnostics…") { Task { await state.export() } }.disabled(state.storageFailed)
                Button("Refresh") { Task { await state.refresh() } }
                Spacer()
                Button("Clear…", role: .destructive) { confirmClear = true }
            }
            Text("Build \(VersionInfo.gitHash)").font(.caption.monospaced()).foregroundStyle(.secondary)
        }.padding(24).frame(width: 660, height: 620)
            .task { await state.refresh() }
            .confirmationDialog("Clear all local diagnostic history?", isPresented: $confirmClear) {
                Button("Clear diagnostics", role: .destructive) {
                    Task { await state.clear() }
                }
            }
    }

}

extension DiagnosticStage {
    var label: String {
        switch self {
        case .microphoneStart: return "Microphone startup"
        case .audioFinalization: return "Audio finalization"
        case .audioValidation: return "Audio validation"
        case .runtimePreparation: return "Runtime preparation"
        case .audioConversion: return "Audio conversion"
        case .voiceModelLoad: return "Voice model load"
        case .voiceInference: return "Voice inference"
        case .voicePipeline: return "Voice pipeline"
        case .formatting: return "Formatting"
        case .writingCleanup: return "Writing cleanup"
        case .writingModelLoad: return "Writing model load"
        case .focusActivation: return "Destination activation"
        case .pasteConfirmation: return "Paste confirmation"
        case .clipboardRestore: return "Clipboard restoration"
        case .historySave: return "History saving"
        case .stopToDelivery: return "Stop to delivery"
        case .total: return "Full session, including capture"
        case .voiceWorkerOperation: return "Voice worker operation"
        case .writingWorkerOperation: return "Writing worker operation"
        }
    }
}
