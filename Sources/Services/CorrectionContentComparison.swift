import CAWCore

/// How much a correction changed, run in Rust (`Vendor/AudioWhisper-Core`,
/// `crates/correction`). `Tests/Reference/ReferenceCorrectionContentComparison.swift`
/// is the Swift it was written in, which the differential tests hold it to.
internal enum CorrectionContentComparison {
    /// Preserve the old character ratio when the changed span is small. Large
    /// spans use tokens, with a finite DP budget; uncertainty keeps the source.
    static func ratio(original: String, corrected: String) -> Double? {
        var ratio = 0.0
        let known = TranscriptCore.withBytes(original, corrected) {
            aw_correction_ratio($0, $1, $2, $3, &ratio)
        }
        return known ? ratio : nil
    }
}
