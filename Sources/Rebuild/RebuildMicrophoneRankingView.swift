import SwiftUI

/// The microphones a recording tries, in the user's order.
struct RebuildMicrophoneRankingView: View {
    @Binding var ranking: [PreferredMicrophone]
    let connected: [RebuildMicrophoneInputs.Input]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if ranking.isEmpty {
                Text("System default").font(.system(size: 13))
            }
            ForEach(Array(ranking.enumerated()), id: \.element.uid) { index, microphone in
                row(microphone, at: index)
            }
            addMenu
            Text("Recording uses the first connected microphone in this list, otherwise the system default. "
                 + "With the lid closed, the built-in microphone is skipped.")
                .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ microphone: PreferredMicrophone, at index: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)").monospacedDigit().foregroundStyle(RebuildTheme.secondaryText)
            Text(Self.label(for: microphone, connected: connected)).lineLimit(1)
            Spacer(minLength: 8)
            Button { ranking.move(microphone.uid, by: -1) } label: {
                Label("Move up", systemImage: "chevron.up").labelStyle(.iconOnly)
            }
            .disabled(index == 0)
            Button { ranking.move(microphone.uid, by: 1) } label: {
                Label("Move down", systemImage: "chevron.down").labelStyle(.iconOnly)
            }
            .disabled(index == ranking.count - 1)
            Button { ranking.removeAll { $0.uid == microphone.uid } } label: {
                Label("Remove", systemImage: "xmark").labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.borderless)
        .frame(maxWidth: 320)
    }

    private var addMenu: some View {
        let unranked = connected.filter { input in !ranking.contains { $0.uid == input.id } }
        return Menu("Add microphone") {
            ForEach(unranked) { input in
                Button(input.name) { ranking.rank(PreferredMicrophone(uid: input.id, name: input.name)) }
            }
        }
        .disabled(unranked.isEmpty)
        .fixedSize()
    }

    /// The live name while connected; otherwise the remembered one, marked.
    static func label(for microphone: PreferredMicrophone, connected: [RebuildMicrophoneInputs.Input]) -> String {
        if let input = connected.first(where: { $0.id == microphone.uid }) { return input.name }
        return "\(microphone.name.isEmpty ? "Saved microphone" : microphone.name) · unavailable"
    }
}
