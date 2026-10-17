import SwiftUI

/// A calm, non-activating HUD. Its size is fixed for the entire capture, even
/// when draft text arrives or recording moves into final transcription.
struct RebuildRecorderView: View {
    @Bindable var session: RebuildSession
    @ObservedObject var recorder: AudioEngineRecorder

    static let silentInputMessage = "No sound from the microphone"
    static func size(preview: Bool) -> CGSize { CGSize(width: 380, height: preview ? 350 : 230) }
    private var silent: Bool { session.phase == .recording && recorder.inputAppearsSilent }
    private var statusTitle: String {
        guard session.phase == .recording else { return "Transcribing…" }
        return silent ? Self.silentInputMessage : "Recording"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusRow
            HStack(spacing: 8) {
                Label(recorder.activeMicrophoneName ?? "Selected microphone", systemImage: "mic")
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Label(session.recordingDestinationName, systemImage: "arrow.up.right")
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.75))
            WaveformContainer(
                status: session.phase == .recording ? .recording : .processing("Transcribing"),
                audioLevel: recorder.audioLevel, waveformSamples: recorder.waveformSamples,
                frequencyBands: recorder.frequencyBands, showsStatusRow: false,
                showsGlassBackground: false, backgroundColor: RebuildTheme.hudWaveformBackground,
                waveformColor: RebuildTheme.hudWaveformForeground, onTap: session.toggleRecording
            )
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityLabel("Microphone waveform")
            if session.livePreview.enabled { RebuildLivePreviewView(preview: session.livePreview) }
            Spacer(minLength: 0)
            controls
        }
        .padding(16)
        .frame(width: Self.size(preview: session.livePreview.enabled).width,
               height: Self.size(preview: session.livePreview.enabled).height)
        .background(RebuildTheme.hudBackground.opacity(0.98), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(RebuildTheme.hudBorder))
        .environment(\.colorScheme, .dark)
        .tint(RebuildTheme.hudAccent)
        .onExitCommand(perform: session.cancel)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle().fill(session.phase == .recording && !silent ? RebuildTheme.recording : RebuildTheme.warning)
                .frame(width: 7, height: 7).accessibilityHidden(true)
            Text(statusTitle)
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let start = session.recordingStartedAt {
                RebuildElapsedTime(start: start).font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("Final transcription in progress")
            }
        }.frame(height: 28)
    }

    private var controls: some View {
        HStack {
            Button(action: session.cancel) { Text("Cancel").frame(minWidth: 64) }
                .buttonStyle(RebuildHUDButtonStyle())
                .help("Cancel (Esc). Nothing is copied or saved.")
            Spacer()
            Button(action: session.finishRecording) {
                Label(session.phase == .recording ? "Stop & transcribe" : "Transcribing…", systemImage: "stop.fill")
                    .frame(minWidth: 140)
            }
            .buttonStyle(RebuildHUDButtonStyle(prominent: true))
            .disabled(session.phase != .recording)
        }
    }
}

struct RebuildLivePreviewView: View {
    let preview: RebuildLivePreview

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Live preview", systemImage: "text.bubble")
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(preview.updating ? "Updating…" : "Recent speech · draft").font(.system(size: 10.5))
            }.foregroundStyle(RebuildTheme.secondaryText)
            Text(preview.text.isEmpty ? preview.message : preview.text)
                .font(.system(size: 13)).lineSpacing(2)
                .foregroundStyle(preview.text.isEmpty ? RebuildTheme.secondaryText : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 55, maxHeight: 55, alignment: .topLeading)
                .lineLimit(3).truncationMode(.head).accessibilityLabel("Live transcript draft")
            if !preview.text.isEmpty, preview.paused {
                Text(preview.message).font(.system(size: 11)).foregroundStyle(RebuildTheme.warning)
            }
        }
        .padding(10)
        .background(RebuildTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
