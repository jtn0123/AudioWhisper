import Foundation

internal enum CorrectionContentComparison {
    private static let comparisonBudget = 1_000_000
    private static let maximumCharacters = 250_000

    /// Preserve the old character ratio when the changed span is small. Large
    /// spans use tokens, with a finite DP budget; uncertainty keeps the source.
    static func ratio(original: String, corrected: String) -> Double? {
        guard original.utf16.count <= maximumCharacters, corrected.utf16.count <= maximumCharacters else { return nil }
        let source = Array(original)
        let edited = Array(corrected)
        if let distance = distance(source, edited) {
            return Double(distance) / Double(max(1, source.count, edited.count))
        }
        let sourceTokens = tokens(original)
        let editedTokens = tokens(corrected)
        guard let distance = distance(sourceTokens, editedTokens) else { return nil }
        return Double(distance) / Double(max(1, sourceTokens.count, editedTokens.count))
    }

    private static func tokens(_ text: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}_]+|[^\s]"#) else { return [] }
        return expression.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            return text[range].lowercased()
        }
    }

    private static func distance<Element: Equatable>(_ source: [Element], _ edited: [Element]) -> Int? {
        var prefix = 0
        while prefix < min(source.count, edited.count), source[prefix] == edited[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(source.count, edited.count) - prefix,
              source[source.count - suffix - 1] == edited[edited.count - suffix - 1] { suffix += 1 }
        let sourceCount = source.count - prefix - suffix
        let editedCount = edited.count - prefix - suffix
        if sourceCount == 0 || editedCount == 0 { return max(sourceCount, editedCount) }
        guard sourceCount <= comparisonBudget / editedCount else { return nil }
        let left = Array(source[prefix..<(source.count - suffix)])
        let right = Array(edited[prefix..<(edited.count - suffix)])
        var previous = Array(0...right.count)
        var current = previous
        for leftIndex in 1...left.count {
            current[0] = leftIndex
            for rightIndex in 1...right.count {
                current[rightIndex] = min(
                    previous[rightIndex] + 1, current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + (left[leftIndex - 1] == right[rightIndex - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
