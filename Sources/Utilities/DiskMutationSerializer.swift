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

    /// Cancel the owned operation and wait until its resources have closed.
    func cancel(key: Key) async {
        guard let task = inFlight[key] else { return }
        task.cancel()
        _ = await task.result
    }
}

/// Best-effort SHA-256 integrity check for cached model files.
///
/// After a successful download, callers record a hash of a representative
/// file (`config.json` for WhisperKit, `refs/main` for MLX/Parakeet). Before
/// loading a cached model, callers verify against that record. If nothing is
/// recorded yet — a cache from before this check existed — `verify` records
/// one and passes (trust-on-first-use), so old caches keep working without a
/// forced redownload.
///
/// What anchors the *first* record (ADR 0006):
///   * **MLX / Parakeet models the app ships** — the download fetches the
///     commit pinned in `ModelPins` and points `refs/main` at it, so the record
///     taken right after it vouches for exactly that commit. This replaced a
///     table of known-good hashes (`knownHashes`) that was never populated and
///     could not safely be: with downloads following `main`, a pinned hash
///     would have rejected every install the moment a repo changed upstream.
///   * **WhisperKit models** — WhisperKit's download has no revision parameter,
///     so the first download is trusted as fetched over TLS.
///   * **User-added repos** — likewise trusted at first fetch, by definition.
///
/// What it catches, stated honestly (audit item E3):
///   * **Cache corruption and truncated/interrupted writes** — reliably.
///   * **The cache being repointed** at a different revision afterwards (for
///     MLX/Parakeet, `refs/main` changing) — reliably.
///   * **Local tampering** — only partly. The record lives in app-owned storage
///     rather than beside the model, which removes the trivial rewrite-both-files
///     case, but a local process running as the user can still reach both. The
///     app is unsandboxed (ADR 0001), so there is no boundary here that a
///     determined local attacker cannot cross. Nor is every byte hashed: only
///     the representative file, since hashing gigabytes of weights on every
///     cache check would block for seconds.
internal enum ModelIntegrity {
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

    /// Verify the integrity of a cached model's representative file against
    /// its recorded hash, recording one if none exists yet (see the type doc).
    ///
    /// Throws `ModelIntegrityError.mismatch` when the file no longer matches.
    static func verify(at modelURL: URL) throws {
        let actual = try sha256(of: modelURL)

        // E3: reads the app-owned record first, then any pre-E3 in-place
        // sidecar, so existing caches keep working across the move.
        if let stored = storedHash(for: modelURL) {
            guard stored.lowercased() == actual.lowercased() else {
                throw ModelIntegrityError.mismatch(expected: stored, actual: actual)
            }
        } else {
            // Nothing recorded yet — trust-on-first-use; persist for next time.
            try actual.write(to: sidecarURL(for: modelURL), atomically: true, encoding: .utf8)
        }
    }

    /// Where the trust-on-first-use hash for `modelURL` is stored.
    ///
    /// Audit item E3: this used to be `modelURL.appendingPathExtension(...)` —
    /// a plain text file sitting in the model's own directory under
    /// `~/.cache/huggingface`. That does not survive the threat the doc comment
    /// above names ("tampering by another local process"): anything able to
    /// rewrite the model could rewrite the hash vouching for it, in the same
    /// directory, and the check would pass. The app ships unsandboxed
    /// (ADR 0001), so there is no OS-level protection either.
    ///
    /// The record now lives in app-controlled storage under Application
    /// Support, keyed by a hash of the model's path. That does not stop a
    /// determined local attacker — nothing at this layer can — but it removes
    /// the trivial rewrite-both-files case and puts the record somewhere the
    /// app owns rather than somewhere any tool that manages the HF cache may
    /// clobber.
    ///
    /// Falls back to the old in-place location if Application Support is
    /// unavailable, so verification degrades rather than failing closed.
    private static func sidecarURL(for modelURL: URL) -> URL {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return modelURL.appendingPathExtension(legacySidecarExtension)
        }

        let dir = base
            .appendingPathComponent("AudioWhisper", isDirectory: true)
            .appendingPathComponent("model-integrity", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Key on the standardised path so the same model always maps to the
        // same record. Hashed rather than escaped: model paths are long and
        // contain separators, and this keeps the filename flat and bounded.
        let key = sha256(ofString: modelURL.standardizedFileURL.path)
        return dir.appendingPathComponent("\(key).integrity")
    }

    /// Pre-E3 sidecar location, still read as a fallback so an existing cache
    /// is not forced into a redownload by the move.
    private static let legacySidecarExtension = "audiowhisper-integrity"

    private static func legacySidecarURL(for modelURL: URL) -> URL {
        modelURL.appendingPathExtension(legacySidecarExtension)
    }

    private static func sha256(ofString value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the recorded hash, preferring the app-owned location and falling
    /// back to a pre-E3 in-place sidecar.
    private static func storedHash(for modelURL: URL) -> String? {
        for url in [sidecarURL(for: modelURL), legacySidecarURL(for: modelURL)] {
            if let raw = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

internal enum ModelIntegrityError: LocalizedError {
    case mismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case let .mismatch(expected, actual):
            return "Model integrity check failed (expected \(expected.prefix(8))…, got \(actual.prefix(8))…). The cached model may be corrupted; re-download it from Settings."
        }
    }
}
