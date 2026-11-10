// The Swift this check was written in, before it moved to Rust
// (Vendor/AudioWhisper-Core). Kept, renamed, only as the reference that
// CorrectionGateDifferentialTests holds the Rust to. Don't change it to make
// a test pass: a difference is the Rust's to fix.
//
// The pure parts of SemanticCorrectionService (safeMerge and what it uses) and
// DictationWriting.accepted; the model, prompt and settings code stays in Sources.

import Foundation
@testable import AudioWhisper

internal enum ReferenceSemanticCorrection {
    // One conservative bound for grammar cleanup in every app.
    static let maxChangeRatio = 0.6

    /// Threshold for switching to the bounded content comparison.
    /// At ~4k chars the DP runs in well under a second; above that, a 30+ minute
    /// transcript uses a bounded changed-span/token comparison instead.
    static let safeMergeLengthCap = 4000

    static func safeMerge(original: String, corrected: String, maxChangeRatio: Double) -> String {
        guard !corrected.isEmpty,
              ReferenceCorrectionIntegrity.allows(original: original, corrected: corrected) else { return original }
        if max(original.count, corrected.count) > safeMergeLengthCap {
            guard let ratio = ReferenceCorrectionContentComparison.ratio(original: original, corrected: corrected),
                ratio <= maxChangeRatio else { return original }
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

/// `DictationWriting`, reduced to the operation `accepted` reads.
struct ReferenceDictationWriting {
    var operation: WritingOperation = .cleanup

    func accepted(original: String, output: String) -> String {
        if operation == .cleanup {
            return ReferenceSemanticCorrection.safeMerge(original: original, corrected: output,
                                                       maxChangeRatio: ReferenceSemanticCorrection.maxChangeRatio)
        }
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, result.count <= max(256, original.count * 4),
              ReferenceCorrectionIntegrity.allows(original: original, corrected: result, allowFraming: true) else {
            return original
        }
        return result
    }
}
