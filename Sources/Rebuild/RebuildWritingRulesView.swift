import SwiftUI

/// Vocabulary and rule-based formatting. Unlike cleanup these need no model:
/// they run on every transcript from either engine.
struct RebuildWritingRulesCard: View {
    @AppDefault(\.customVocabulary) private var vocabulary
    @AppDefault(\.removeFillerWords) private var removeFillers
    @AppDefault(\.spokenPunctuation) private var spokenPunctuation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Words & formatting").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text("Applied to every transcript before any cleanup. No model needed.")
                .font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText)
            Toggle("Remove “uh” and “um”", isOn: $removeFillers)
            Toggle("Turn spoken “comma”, “period” and “new line” into punctuation", isOn: $spokenPunctuation)
            Divider()
            Text("Vocabulary").font(.system(size: 12.5, weight: .semibold))
            Text(
                "One word per line keeps its spelling, such as Kubernetes. Use “heard -> written” to rewrite "
                    + "a phrase. Whisper models also listen for these words."
            )
            .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $vocabulary)
                .font(.system(size: 12.5, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 90, maxHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(RebuildTheme.border))
                .accessibilityLabel("Vocabulary")
            Text(Self.summary(of: CustomVocabulary(parsing: vocabulary)))
                .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
        }.rebuildCard()
    }

    static func summary(of vocabulary: CustomVocabulary) -> String {
        guard !vocabulary.isEmpty else { return "No vocabulary yet." }
        let terms = vocabulary.terms.count
        let rewrites = vocabulary.replacements.count
        return [
            terms > 0 ? "\(terms) \(terms == 1 ? "word" : "words")" : nil,
            rewrites > 0 ? "\(rewrites) \(rewrites == 1 ? "rewrite" : "rewrites")" : nil
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
