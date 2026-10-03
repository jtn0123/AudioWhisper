import Foundation

/// Least-recently-used bookkeeping, extracted from `WhisperKitCache`.
///
/// The cache actor owns the expensive `WhisperKit` instances; this type owns
/// only the access timestamps and the *decision* about which key to drop. The
/// split exists so the eviction policy is testable without instantiating
/// WhisperKit, which requires a downloaded multi-hundred-megabyte model and is
/// therefore reachable only from the nightly end-to-end job.
///
/// Audit item D2: `LRUCacheTests` previously covered this policy by building a
/// dictionary inside the test and re-sorting it with a copy of the production
/// expression — it exercised `Dictionary.sorted`, not the cache. Those tests
/// passed whatever the cache did. They now drive this type directly.
///
/// Tie-breaking is unspecified: when two keys share an access timestamp, either
/// may be reported as least-recently-used. This matches the previous
/// `sorted(by:).first` behaviour, which was equally arbitrary on ties.
internal struct LRUAccessTracker<Key: Hashable> {
    private var accessTimes: [Key: Date] = [:]

    var count: Int { accessTimes.count }

    var trackedKeys: Set<Key> { Set(accessTimes.keys) }

    /// Records an access, inserting the key or refreshing its timestamp.
    ///
    /// `date` is injectable so tests can pin ordering instead of relying on
    /// wall-clock gaps between calls, which are not guaranteed to be distinct
    /// at `Date()`'s resolution.
    mutating func touch(_ key: Key, at date: Date = Date()) {
        accessTimes[key] = date
    }

    /// Drops a key's bookkeeping. No-op if the key is not tracked.
    mutating func forget(_ key: Key) {
        accessTimes.removeValue(forKey: key)
    }

    mutating func removeAll() {
        accessTimes.removeAll()
    }

    /// The least recently accessed key, or `nil` when nothing is tracked.
    ///
    /// `min(by:)` rather than `sorted(by:).first` — same result, O(n) instead
    /// of O(n log n).
    func leastRecentlyUsed() -> Key? {
        accessTimes.min { $0.value < $1.value }?.key
    }

    /// Every tracked key, most recently accessed first.
    func mostRecentlyUsedFirst() -> [Key] {
        accessTimes.sorted { $0.value > $1.value }.map(\.key)
    }

    /// Keys that should be evicted to keep only the single most recently used
    /// entry. Empty when fewer than two keys are tracked.
    func keysToEvictKeepingMostRecent() -> [Key] {
        Array(mostRecentlyUsedFirst().dropFirst())
    }
}
