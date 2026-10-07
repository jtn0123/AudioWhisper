import Foundation
enum Cleaner {
    static func cleanTranscriptionText(_ text: String) -> String {
        var cleanedText = text

        // Remove bracketed markers iteratively to handle nested cases
        var previousLength = 0
        while cleanedText.count != previousLength {
            previousLength = cleanedText.count
            cleanedText = cleanedText.replacingOccurrences(
                of: "\\[[^\\[\\]]*\\]",
                with: "",
                options: .regularExpression
            )
        }

        // Remove parenthetical markers iteratively to handle nested cases
        previousLength = 0
        while cleanedText.count != previousLength {
            previousLength = cleanedText.count
            cleanedText = cleanedText.replacingOccurrences(
                of: "\\([^\\(\\)]*\\)",
                with: "",
                options: .regularExpression
            )
        }

        // Clean up whitespace and return
        return cleanedText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

}
enum Guard {
    static let safeMergeLengthCap = 4000

    static func safeMerge(original: String, corrected: String, maxChangeRatio: Double) -> String {
        guard !corrected.isEmpty else { return original }
        // H20: For long inputs, fall back to a cheap length-ratio heuristic so
        // we don't run an O(m*n) edit-distance DP on tens of thousands of chars.
        if max(original.count, corrected.count) > safeMergeLengthCap {
            let denom = max(original.count, corrected.count)
            guard denom > 0 else { return original }
            let lengthDelta = Double(abs(original.count - corrected.count)) / Double(denom)
            if lengthDelta > maxChangeRatio { return original }
            return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let ratio = normalizedEditDistance(a: original, b: corrected)
        if ratio > maxChangeRatio { return original }
        return corrected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Computes normalized edit distance using space-efficient 2-row DP.
    /// Memory: O(min(m,n)) instead of O(m*n) for full matrix.
    static func normalizedEditDistance(a lhs: String, b rhs: String) -> Double {
        if lhs == rhs { return 0 }
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let lhsCount = lhsChars.count
        let rhsCount = rhsChars.count
        if lhsCount == 0 || rhsCount == 0 { return 1 }

        // Optimize: ensure we iterate over shorter string in inner loop
        let (shorter, longer): ([Character], [Character])
        if lhsCount > rhsCount {
            shorter = rhsChars
            longer = lhsChars
        } else {
            shorter = lhsChars
            longer = rhsChars
        }

        // Two-row DP: only keep current and previous rows
        var previousRow = Array(0...shorter.count)
        var currentRow = Array(repeating: 0, count: shorter.count + 1)

        for longerIndex in 1...longer.count {
            currentRow[0] = longerIndex
            for shorterIndex in 1...shorter.count {
                let cost = longer[longerIndex - 1] == shorter[shorterIndex - 1] ? 0 : 1
                currentRow[shorterIndex] = min(
                    previousRow[shorterIndex] + 1,      // deletion
                    currentRow[shorterIndex - 1] + 1,   // insertion
                    previousRow[shorterIndex - 1] + cost // substitution
                )
            }
            swap(&previousRow, &currentRow)
        }

        let dist = previousRow[shorter.count]
        let denom = max(lhsChars.count, rhsChars.count)
        return Double(dist) / Double(denom)
    }
}

let bracketed = "Send the report (including taxes) to Jordan [the editor]."
print("bracketed: \(Cleaner.cleanTranscriptionText(bracketed))")
let code = "let ids = [1, 2, 3]; print(ids[0])"
print("code: \(Cleaner.cleanTranscriptionText(code))")
for count in [600, 900] {
  let original = String(repeating: "alpha ", count: count)
  let corrected = String(repeating: "bravo ", count: count)
  let result = Guard.safeMerge(original: original, corrected: corrected, maxChangeRatio: 0.6)
  print("unrelated chars=\(original.count) accepted=\(result == corrected.trimmingCharacters(in: .whitespacesAndNewlines))")
}
let source="Do not delete the backup."
let output="Delete the backup."
print("negation loss accepted=\(Guard.safeMerge(original: source, corrected: output, maxChangeRatio: 0.6) == output)")
