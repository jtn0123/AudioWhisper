import Foundation
import CryptoKit

/// Serializes disk-mutating operations keyed by a Hashable identifier.
///
/// Two callers requesting the SAME key (e.g. downloading the same model)
/// block each other and share the result of a single operation. Two callers
/// with DIFFERENT keys (e.g. downloading two different models) proceed in
/// parallel.
///
/// Used by `MLXModelManager` and `ModelManager` to prevent races during
/// model downloads and cache directory creation. The pattern was first
/// introduced for venv setup in `UvBootstrap.VenvSerializer` (Phase 3
/// of the grade-report sweep); this generalizes it.
internal actor DiskMutationSerializer<Key: Hashable & Sendable> {
    private var inFlight: [Key: Task<Void, Error>] = [:]

    /// Run `op` serialized on `key`. Concurrent callers for the same key
    /// will await the in-flight task instead of starting a new one.
    ///
    /// The `inFlight` entry is cleared deterministically — within this
    /// actor-isolated context, immediately after the task finishes (success
    /// OR failure) — so a FAILED operation is never cached and re-served to a
    /// later caller that arrives in the window before cleanup. A previous
    /// implementation used a detached `Task { clear() }`, leaving the failed
    /// task lingering in `inFlight` until that detached task happened to run.
    func run(key: Key, _ op: @Sendable @escaping () async throws -> Void) async throws {
        if let existing = inFlight[key] {
            return try await existing.value
        }
        let task = Task<Void, Error> { try await op() }
        inFlight[key] = task

        // Await the result, then clear synchronously on this actor before
        // returning, so success and failure are both un-cached deterministically.
        // While this task is in flight, concurrent same-key callers await the
        // existing entry rather than installing a new one, so no other writer
        // can have replaced `inFlight[key]` by the time we get here.
        let result = await task.result
        inFlight[key] = nil
        try result.get()
    }
}

/// Best-effort SHA-256 integrity check for cached model files.
///
/// After a successful download, callers record a hash of a representative
/// file (typically a manifest or small config). Before loading a cached
/// model, callers verify against that recorded hash.
///
/// Two verification modes (audit item E1):
///
///   1. **Known-good hash** — for models the app itself ships/recommends
///      (`knownHashes` table below). The representative file's hash is
///      compared against a hash baked into this build, exactly like
///      `UvBootstrap.verifyBundledUvIfNeeded` does for the bundled `uv`
///      binary. A mismatch is a HARD FAIL — this is what prevents a
///      poisoned *first* download from being trusted.
///
///   2. **Trust-on-first-use** — for user-added models we have no shipped
///      hash for. If no sidecar exists yet, `verify` records one and
///      returns successfully; later launches verify against it. This keeps
///      pre-integrity caches and arbitrary user models working without a
///      forced redownload.
///
/// This is defense in depth, not cryptographic assurance over every byte:
/// TLS already protects downloads in transit. The check guards against
/// cache corruption, partial/interrupted writes that left a truncated
/// file, and tampering by another local process.
internal enum ModelIntegrity {
    /// Known-good SHA-256 hashes of the *representative integrity file* for
    /// models the app ships or recommends. Keyed by the caller's model
    /// identifier: `WhisperModel.rawValue` for WhisperKit models, or the
    /// HuggingFace `repo` string for MLX/Parakeet models.
    ///
    /// When an identifier is present here, `verify` uses known-good-hash mode
    /// (hard fail on mismatch) instead of trust-on-first-use, so a poisoned
    /// first download cannot be silently accepted.
    ///
    /// IMPORTANT: This table is intentionally EMPTY. The real hashes are not
    /// known at the time this mechanism was built and fabricating values
    /// would be worse than an empty table (it would reject every legitimate
    /// download). Populating it later is a one-liner per model, e.g.:
    ///
    ///     "openai_whisper-base": "a1b2c3…",                       // WhisperKit
    ///     "mlx-community/parakeet-tdt-0.6b-v2": "d4e5f6…",        // MLX/Parakeet
    ///
    /// The hash must be the SHA-256 of the representative file that the
    /// matching caller passes to `record`/`verify` (`config.json` for
    /// WhisperKit via `ModelManager.representativeFileURL`, `refs/main` for
    /// MLX via `MLXModelManager.integrityFileURL`). Compute it from a release
    /// build's cached download and paste it in here.
    ///
    /// >>> ACTION REQUIRED <<< Populate this table with real release hashes
    /// before shipping; until then app-shipped models silently fall through
    /// to trust-on-first-use (the documented gap for audit item E1).
    static let knownHashes: [String: String] = [:]

    /// Returns the known-good hash for `modelIdentifier`, or nil if the model
    /// is not one the app ships (user-added model → trust-on-first-use).
    static func knownHash(for modelIdentifier: String?) -> String? {
        guard let modelIdentifier else { return nil }
        return knownHashes[modelIdentifier]
    }
    /// Compute SHA-256 of file at `url`. Streams the file in 64KB chunks so
    /// gigabyte-sized model files don't blow up memory.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 64 * 1024
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Compute and persist a sidecar hash for a model file.
    /// Overwrites any pre-existing sidecar so a fresh download resets the
    /// integrity reference.
    static func record(at modelURL: URL) throws {
        let hash = try sha256(of: modelURL)
        try hash.write(to: sidecarURL(for: modelURL), atomically: true, encoding: .utf8)
    }

    /// Verify the integrity of a cached model's representative file.
    ///
    /// If `modelIdentifier` is in `knownHashes` (an app-shipped model), the
    /// file's hash is compared against that known-good value and any mismatch
    /// is a HARD FAIL — even on the very first download — defeating a poisoned
    /// first download. Otherwise falls back to trust-on-first-use against a
    /// sidecar hash.
    ///
    /// Throws `ModelIntegrityError.pinnedMismatch` when an app-shipped model
    /// fails its known-good hash, or `.mismatch` when a TOFU sidecar differs.
    static func verify(at modelURL: URL, modelIdentifier: String? = nil) throws {
        let actual = try sha256(of: modelURL)

        if let pinned = knownHash(for: modelIdentifier) {
            // App-shipped model: verify against the hash baked into this build.
            // Hard fail on mismatch — no trust-on-first-use escape hatch.
            guard pinned.lowercased() == actual.lowercased() else {
                throw ModelIntegrityError.pinnedMismatch(
                    model: modelIdentifier ?? "<unknown>",
                    expected: pinned,
                    actual: actual
                )
            }
            // Keep the sidecar in sync so quick TOFU checks elsewhere agree.
            try? actual.write(to: sidecarURL(for: modelURL), atomically: true, encoding: .utf8)
            return
        }

        // User-added model: trust-on-first-use against a sidecar hash.
        let sidecar = sidecarURL(for: modelURL)
        if let stored = try? String(contentsOf: sidecar, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty {
            guard stored.lowercased() == actual.lowercased() else {
                throw ModelIntegrityError.mismatch(expected: stored, actual: actual)
            }
        } else {
            // No sidecar yet — trust-on-first-use; persist for next time.
            try actual.write(to: sidecar, atomically: true, encoding: .utf8)
        }
    }

    /// Returns true if integrity verification passes; false on any mismatch,
    /// missing-file error, or unreadable file. Never throws — useful for
    /// background verification where we don't want to surface noise.
    static func quietVerify(at modelURL: URL, modelIdentifier: String? = nil) -> Bool {
        do {
            try verify(at: modelURL, modelIdentifier: modelIdentifier)
            return true
        } catch {
            return false
        }
    }

    private static func sidecarURL(for modelURL: URL) -> URL {
        modelURL.appendingPathExtension("audiowhisper-integrity")
    }
}

internal enum ModelIntegrityError: LocalizedError {
    case mismatch(expected: String, actual: String)
    case pinnedMismatch(model: String, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case let .mismatch(expected, actual):
            return "Model integrity check failed (expected \(expected.prefix(8))…, got \(actual.prefix(8))…). The cached model may be corrupted; re-download it from Settings."
        case let .pinnedMismatch(model, expected, actual):
            return "Integrity check failed for app-provided model \"\(model)\" (expected \(expected.prefix(8))…, got \(actual.prefix(8))…). The download does not match the version shipped with AudioWhisper and was rejected. Re-download it from Settings or reinstall AudioWhisper from a trusted source."
        }
    }
}
