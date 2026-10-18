import SwiftUI

/// Vocabulary and rule-based formatting. Unlike cleanup these need no model:
/// they run on every transcript from either engine.
struct RebuildWritingRulesCard: View {
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
            RebuildVocabularyEditor()
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
