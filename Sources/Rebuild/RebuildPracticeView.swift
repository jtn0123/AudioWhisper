import SwiftUI

struct RebuildPracticeView: View {
    let session: RebuildSession
    var recorder: AudioEngineRecorder?
    var copy: (String) -> Void = PasteManager.copyToClipboard
    @AppStorage("rebuild.practiceCompleted", store: AppDefaults.defaults) private var completed = false
    @State private var expected = ""
    @State private var pasted = ""
    @FocusState private var pasteFocused: Bool

    private var hasResult: Bool { session.isPractice && session.phase == .completed && !session.transcript.isEmpty }
    private var recording: Bool { session.isPractice && session.phase == .recording }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RebuildStepHeader(number: 3, title: "Try your first dictation", done: completed)
            Text("Say a short sentence, then try pasting it here. Practice stays out of your library and other apps.")
                .font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText)
            if recording {
                if let start = session.recordingStartedAt { RebuildElapsedTime(start: start) }
                if let recorder { RebuildPracticeMeter(recorder: recorder) }
            }
            HStack(spacing: 10) {
                if recording {
                    Button("Stop practice recording", action: session.finishRecording).buttonStyle(.borderedProminent)
                    Button("Cancel practice", action: session.cancel)
                } else {
                    Button(completed ? "Practice again" : "Record a practice sentence") {
                        expected = ""
                        pasted = ""
                        session.startPractice()
                    }
                    .disabled(!session.readiness.ready || session.phase.isBusy
                        || session.isInstalling || session.maintenanceInProgress)
                    .buttonStyle(.borderedProminent)
                    if session.isPractice && session.phase.isBusy {
                        ProgressView().controlSize(.small).accessibilityLabel(session.recordingActionTitle)
                        Button("Cancel practice", action: session.cancel)
                    }
                }
            }
            if !session.readiness.ready {
                Text("Complete microphone and voice model setup above first.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            }
            if hasResult {
                Text(session.transcript).font(.system(size: 13)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy practice text") {
                    expected = session.transcript
                    copy(expected)
                    pasted = ""
                    pasteFocused = true
                }
                Text("Click Copy practice text, then press Command V in the field below.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                TextEditor(text: $pasted).font(.system(size: 13)).frame(height: 60)
                    .focused($pasteFocused).accessibilityLabel("Practice paste field")
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(RebuildTheme.border))
                    .onChange(of: pasted) { _, value in
                        if Self.matches(value, expected: expected) { completed = true }
                    }
            }
            if session.isPractice, session.phase == .failed, let notice = session.notice {
                RebuildCallout(tone: .error, message: notice)
            }
            if completed {
                let message = "Practice complete. Use Record, or enable a recording shortcut in Preferences."
                RebuildCallout(tone: .success, message: message)
                    .rebuildAnnouncement(message, onAppear: true)
            }
        }.rebuildCard()
    }

    static func matches(_ pasted: String, expected: String) -> Bool {
        !expected.isEmpty && pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            == expected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct RebuildPracticeMeter: View {
    @ObservedObject var recorder: AudioEngineRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(recorder.audioLevel)).accessibilityLabel("Practice microphone level")
            Text(recorder.activeMicrophoneName ?? "Selected microphone").font(.system(size: 11.5))
                .foregroundStyle(RebuildTheme.secondaryText)
            if recorder.inputAppearsSilent {
                RebuildCallout(tone: .warning, message: RebuildRecorderView.silentInputMessage)
            }
        }
    }
}
