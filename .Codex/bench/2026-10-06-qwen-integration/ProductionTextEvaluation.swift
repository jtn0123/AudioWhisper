import Foundation
enum Guard {
    static func maxChangeRatio(for categoryId: String) -> Double {
        switch categoryId {
        case "terminal", "coding":
            return 0.85
        default:
            return 0.6
        }
    }

    /// Hard ceiling above which we skip the O(m*n) Levenshtein computation.
    /// At ~4k chars the DP runs in well under a second; above that, a 30+ minute
    /// transcript can stall the correction pipeline for many seconds. Load-bearing.
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

while let line = readLine() {
    let input = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    let text = input["text"] as! String
    var output = input
    if input["kind"] as? String == "writing" {
        let original = input["input"] as! String
        let ratio = Guard.maxChangeRatio(for: input["category"] as! String)
        let delivered = Guard.safeMerge(original: original, corrected: text, maxChangeRatio: ratio)
        output["delivered"] = delivered
        output["guard_rejected"] = text != original && delivered == original
        output["edit_ratio"] = Guard.normalizedEditDistance(a: original, b: text)
        output["max_change_ratio"] = ratio
    } else {
        output["delivered"] = Cleaner.cleanTranscriptionText(text)
    }
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print(String(data: data, encoding: .utf8)!)
}
