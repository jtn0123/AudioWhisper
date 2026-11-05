import SwiftUI

/// The recorder's closing card: why dictation stopped short, and what to do.
struct RebuildRecorderOutcomeView: View {
    @Bindable var session: RebuildSession
    let outcome: RebuildRecorderOutcome

    private var isFailure: Bool {
        if case .failed = outcome { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "doc.on.clipboard")
                    .foregroundStyle(isFailure ? RebuildTheme.warning : RebuildTheme.hudAccent)
                    .accessibilityHidden(true)
                Text(outcome.title)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(height: 28)
            Text(outcome.message)
                .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.82))
                .lineLimit(5).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            controls
        }
        .accessibilityElement(children: .contain)
        .onHover(perform: session.holdOutcome)
    }

    private var controls: some View {
        HStack {
            Button(action: session.dismissOutcome) { Text("Dismiss").frame(minWidth: 64) }
                .buttonStyle(RebuildHUDButtonStyle())
                .help("Hide this message (Esc).")
            Spacer()
            if isFailure {
                Button(action: session.openWorkspaceFromRecorder) { Text("Open AudioWhisper") }
                    .buttonStyle(RebuildHUDButtonStyle())
            }
            if isFailure, session.canRetry {
                Button(action: session.retryFromRecorder) {
                    Label("Retry", systemImage: "arrow.clockwise").frame(minWidth: 80)
                }
                .buttonStyle(RebuildHUDButtonStyle(prominent: true))
            }
        }
    }
}
