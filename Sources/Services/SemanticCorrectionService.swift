import Foundation

import os.log

/// The result of attempting a semantic-correction pass.
///
/// Returned from `SemanticCorrectionService.correctWithOutcome(...)` so callers
/// can distinguish a successful correction from a no-op (user disabled it) or
/// a silent failure (e.g. MLX subprocess crashed). The legacy
/// `correct(...) -> String` API erases this distinction; new callers should
/// prefer the outcome-aware API. See audit item B2.
internal enum CorrectionOutcome {
    /// Correction was applied successfully; associated value is the corrected text.
    case applied(String)
    /// Correction was disabled by user settings; original text is returned unchanged.
    case skipped(String)
    /// A safety check rejected the edit; keep the original visibly.
    case rejected(String)
    /// Correction was attempted but failed; the original text is returned as a fallback.
    case failed(Error, fallback: String)

    /// Convenience: the text to use in the UI, regardless of outcome.
    var text: String {
        switch self {
        case .applied(let value), .skipped(let value), .rejected(let value): return value
        case .failed(_, fallback: let value): return value
        }
    }
}

/// Post-processes raw transcripts to fix typos, punctuation, and filler words.
/// Mode is read from preferences: off / local MLX / cloud (uses the active
/// transcription provider).
internal final class SemanticCorrectionService {
    private let mlxService: MLXCorrectionService
    private let preparePython: () async throws -> URL
    private let logger = Logger(subsystem: "com.audiowhisper.app", category: "SemanticCorrection")

    init(
        mlxService: MLXCorrectionService = MLXCorrectionService(),
        preparePython: @escaping () async throws -> URL = { try await UvBootstrap.ensureVenv() }
    ) {
        self.mlxService = mlxService
        self.preparePython = preparePython
    }

    /// Applies semantic correction to `text`. Reads `semanticCorrectionMode` from
    /// `UserDefaults` and picks: off (returns input unchanged) or local MLX. The
    /// cleanup prompt is the same for every destination.
    /// On failure, returns the original `text` silently — see audit item B2 and
    /// prefer `correctWithOutcome(...)` for new code.
    ///
    /// This method is preserved as a thin wrapper around `correctWithOutcome` so
    /// existing call sites keep their `async -> String` contract unchanged.
    func correct(text: String, providerUsed: TranscriptionProvider, sourceAppBundleId: String? = nil) async -> String {
        await correctWithOutcome(text: text, providerUsed: providerUsed, sourceAppBundleId: sourceAppBundleId).text
    }

    /// Outcome-aware semantic correction API.
    ///
    /// Preferred entry point for new callers (and for surfacing failures to the
    /// UI per audit item B2). Returns:
    /// - `.skipped(text)` if `semanticCorrectionMode == .off`
    /// - `.applied(corrected)` if correction ran and produced text (possibly
    ///   identical to the input after safe-merge)
    /// - `.failed(error, fallback: text)` if the correction pipeline threw;
    ///   the fallback is the unchanged original text so callers can still
    ///   show something useful.
    func correctWithOutcome(
        text: String,
        providerUsed: TranscriptionProvider,
        sourceAppBundleId: String? = nil,
        mode: SemanticCorrectionMode? = nil,
        modelRepo: String? = nil
    ) async -> CorrectionOutcome {
        let mode = mode ?? AppDefaults.semanticCorrectionMode
        let modelRepo = modelRepo ?? AppDefaults.semanticCorrectionModelRepo

        switch mode {
        case .off:
            return .skipped(text)
        case .localMLX:
            // Allow local MLX correction regardless of STT provider
            logger.info("Running local MLX correction")
            do {
                return try await correctLocallyWithMLXThrowing(text: text, modelRepo: modelRepo)
            } catch {
                logger.error("MLX correction failed: \(error.localizedDescription)")
                return .failed(error, fallback: text)
            }
        }
    }

    /// Throwing variant of `correctLocallyWithMLX`. Used by `correctWithOutcome`
    /// so callers can distinguish success from failure. On non-Apple-Silicon
    /// hosts this returns the input unchanged (treated as a successful no-op,
    /// not a failure — there's nothing to recover from).
    private func correctLocallyWithMLXThrowing(
        text: String, modelRepo: String
    ) async throws -> CorrectionOutcome {
        guard Arch.isAppleSilicon else { return .applied(text) }
        // B1: honour `AppDefaults.semanticCorrectionModelRepo` unconditionally.
        // This used to fall back to Llama-3.2-1B whenever the key was unset,
        // while the Dashboard displayed and badged Qwen3-1.7B as RECOMMENDED —
        // so users on the implicit default saw one model and ran another.
        // Existing installs are pinned to the legacy model by
        // `AppSetupHelper.migrateSemanticCorrectionModelDefault()`.
        let pyURL = try await preparePython()
        let prompt = CorrectionIntegrity.instruction + "\n\n" + CorrectionPrompt.template
        let output = try await mlxService.correct(text: text, modelRepo: modelRepo, pythonPath: pyURL.path, systemPrompt: prompt)
        let merged = Self.safeMerge(
            original: text,
            corrected: output,
            maxChangeRatio: Self.maxChangeRatio
        )
        if merged == text {
            logger.info("MLX correction produced no accepted change (kept original)")
        } else {
            logger.info("MLX correction applied changes")
        }
        if output.trimmingCharacters(in: .whitespacesAndNewlines) != text && merged == text { return .rejected(text) }
        return .applied(merged)
    }

    // One conservative bound for grammar cleanup in every app.
    static let maxChangeRatio = 0.6

    /// Threshold for switching to the bounded content comparison.
    /// At ~4k chars the DP runs in well under a second; above that, a 30+ minute
    /// transcript uses a bounded changed-span/token comparison instead.
    static let safeMergeLengthCap = 4000

    static func safeMerge(original: String, corrected: String, maxChangeRatio: Double) -> String {
        guard !corrected.isEmpty, CorrectionIntegrity.allows(original: original, corrected: corrected) else { return original }
        if max(original.count, corrected.count) > safeMergeLengthCap {
            guard let ratio = CorrectionContentComparison.ratio(original: original, corrected: corrected),
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
