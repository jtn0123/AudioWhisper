import SwiftUI

/// The latest transcript, editable, with copy and original-text recovery.
struct RebuildTranscriptCard: View {
    @Bindable var session: RebuildSession
    @State private var remembering = false
    @State private var correctionSaved = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Transcript").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if !session.transcript.isEmpty {
                    Text("\(UsageMetricsStore.estimatedWordCount(for: session.transcript)) words")
                        .font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText)
                }
                Spacer()
                if !session.transcript.isEmpty {
                    if session.canUseOriginal {
                        Button("Use original", action: session.useOriginalTranscript)
                            .help("Restore and copy your words before writing cleanup")
                    }
                    Button(copied ? "Copied" : "Copy text") {
                        PasteManager.copyToClipboard(session.transcript)
                        copied = true
                    }.keyboardShortcut("c", modifiers: [.command, .shift])
                        .help("Copy transcript (Command Shift C)")
                }
            }.disabled(session.phase.isBusy)
            if session.phase.isBusy {
                RebuildContentState(
                    title: session.phase == .recording ? "Listening…" : "Preparing your transcript…",
                    symbol: "waveform", detail: session.phase == .recording
                        ? "Stop when you’re done. Your final transcript will appear here."
                        : "Processing on this Mac. You can cancel without delivering any text.", busy: true)
            } else if session.transcript.isEmpty {
                RebuildContentState(
                    title: session.phase == .failed ? "No transcript yet" : "A little less typing.",
                    symbol: session.phase == .failed ? "arrow.clockwise" : "text.bubble",
                    detail: session.phase == .failed
                        ? "Your recording hasn’t been delivered. Follow the recovery action above, or start again."
                        : "Your next transcript appears here and is copied automatically. Saving to the library is optional.")
            } else {
                TextEditor(text: $session.transcript).font(.system(size: 14)).scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 240)
                    .accessibilityLabel("Your transcript")
                HStack {
                    Button("Remember a correction…") { remembering = true }
                        .help("Save a corrected word or phrase for future recordings")
                    if correctionSaved {
                        Label("Correction saved", systemImage: "checkmark.circle")
                            .font(.system(size: 12)).foregroundStyle(RebuildTheme.success)
                    }
                }
                if session.pendingHistoryWrites > 0, AppDefaults.transcriptionHistoryEnabled {
                    Label("Saving to your local library…", systemImage: "externaldrive")
                        .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                }
                if let original = session.originalTranscript, original != session.transcript {
                    DisclosureGroup("Compare with original") {
                        Text(original).font(.system(size: 14)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }.disabled(session.phase.isBusy)
                }
            }
        }.rebuildCard()
        .sheet(isPresented: $remembering) {
            RebuildRememberCorrectionView(draft: RebuildVocabularyDocument.correction(
                from: session.deliveredTranscript, to: session.transcript)) { correctionSaved = true }
        }
        .onChange(of: session.transcript) { _, _ in copied = false; correctionSaved = false }
    }
}
