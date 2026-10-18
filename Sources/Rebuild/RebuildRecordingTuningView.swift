import SwiftUI

/// Less common tuning lives under Advanced; existing values are never reset.
struct RebuildRecordingTuningView: View {
    let connected: [RebuildMicrophoneInputs.Input]
    @AppDefault(\.microphoneRanking) private var ranking
    @AppDefault(\.autoBoostMicrophoneVolume) private var boost
    @AppDefault(\.matchCursorContext) private var matchContext
    @AppDefault(\.restoreClipboardAfterPaste) private var restoreClipboard
    @AppDefault(\.enableSmartPaste) private var smartPaste
    @AppDefault(\.waveformStyle) private var waveform
    @AppDefault(\.visualIntensity) private var intensity

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            RebuildFormRow(label: "Input fallbacks") {
                RebuildMicrophoneRankingView(ranking: $ranking, connected: connected)
            }
            RebuildFormRow(label: "Input level") {
                Toggle("Boost microphone input while recording", isOn: $boost)
            }
            RebuildFormRow(label: "Paste behavior") {
                Toggle("Match spacing and capitals to the text before the cursor", isOn: $matchContext)
                Toggle("Put back what was on the clipboard after pasting", isOn: $restoreClipboard)
            }.disabled(!smartPaste)
            RebuildFormRow(label: "Recorder style") {
                Picker("Recorder visual", selection: $waveform) {
                    ForEach(WaveformStyle.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize()
                Picker("Motion intensity", selection: $intensity) {
                    ForEach(VisualIntensity.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize()
                Text("The recorder respects macOS Reduce Motion.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            }
        }
    }
}

struct RebuildPreferredMicrophonePicker: View {
    @Binding var ranking: [PreferredMicrophone]
    let connected: [RebuildMicrophoneInputs.Input]

    var body: some View {
        Picker("Preferred microphone", selection: Binding(get: { ranking.first?.uid ?? "" }, set: select)) {
            Text("System default").tag("")
            ForEach(connected) { Text($0.name).tag($0.id) }
            if let first = ranking.first, !connected.contains(where: { $0.id == first.uid }) {
                Text("\(first.name.isEmpty ? "Saved microphone" : first.name) · unavailable").tag(first.uid)
            }
        }.labelsHidden().frame(maxWidth: 320, alignment: .leading)
    }

    private func select(_ uid: String) {
        guard !uid.isEmpty else { ranking = []; return }
        guard let input = connected.first(where: { $0.id == uid }) else { return }
        var updated = ranking.filter { $0.uid != uid }
        updated.insert(PreferredMicrophone(uid: uid, name: input.name), at: 0)
        ranking = updated
    }
}
