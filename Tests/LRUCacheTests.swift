import XCTest
@testable import AudioWhisper

/// Tests for the LRU eviction policy that `WhisperKitCache` uses to bound the
/// number of live WhisperKit instances.
///
/// Audit item D2: the previous version of this file did not test the cache. Every
/// case built a `[String: Date]` dictionary inside the test body and re-sorted it
/// with a copy of the production expression, then asserted on that — so it
/// exercised `Dictionary.sorted` and would have passed unchanged if
/// `WhisperKitCache` had been deleted. Its own comment conceded the point ("We
/// simulate the sorting logic used in the WhisperKitCache").
///
/// `LRUAccessTracker` was extracted from the cache actor so the policy could be
/// driven directly. Testing it through `LocalWhisperService` is not possible:
/// `WhisperKitCache` is a private actor whose entries are real `WhisperKit`
/// instances, which require a downloaded multi-hundred-megabyte model and are
/// therefore reachable only from the nightly end-to-end job.
final class LRUCacheTests: XCTestCase {

    /// Fixed base date so ordering is pinned rather than depending on wall-clock
    /// gaps between calls, which `Date()` does not guarantee to be distinct.
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func tracker(_ entries: [(WhisperModel, TimeInterval)]) -> LRUAccessTracker<WhisperModel> {
        var lru = LRUAccessTracker<WhisperModel>()
        for (model, offset) in entries {
            lru.touch(model, at: base.addingTimeInterval(offset))
        }
        return lru
    }

    // MARK: - Least-recently-used selection

    func testLeastRecentlyUsedReturnsOldestAccess() {
        let lru = tracker([(.tiny, -100), (.base, -50), (.small, 0)])
        XCTAssertEqual(lru.leastRecentlyUsed(), .tiny)
    }

    func testLeastRecentlyUsedIsNilWhenEmpty() {
        let lru = LRUAccessTracker<WhisperModel>()
        XCTAssertNil(lru.leastRecentlyUsed())
        XCTAssertEqual(lru.count, 0)
    }

    func testLeastRecentlyUsedWithSingleEntryReturnsThatEntry() {
        let lru = tracker([(.base, 0)])
        XCTAssertEqual(lru.leastRecentlyUsed(), .base)
    }

    /// A cache hit must refresh the timestamp, otherwise a model in constant use
    /// would still age out and be reloaded from disk.
    func testTouchingAnEntryMakesItNoLongerLeastRecentlyUsed() {
        var lru = tracker([(.tiny, -100), (.base, -50), (.small, 0)])
        XCTAssertEqual(lru.leastRecentlyUsed(), .tiny, "precondition")

        lru.touch(.tiny, at: base.addingTimeInterval(10))

        XCTAssertEqual(lru.leastRecentlyUsed(), .base,
                       "after re-access, .tiny must no longer be the eviction candidate")
        XCTAssertEqual(lru.count, 3, "re-access must refresh, not insert a duplicate")
    }

    // MARK: - Ordering

    func testMostRecentlyUsedFirstOrdersDescendingByAccessTime() {
        let lru = tracker([(.tiny, -100), (.base, -50), (.small, 0)])
        XCTAssertEqual(lru.mostRecentlyUsedFirst(), [.small, .base, .tiny])
    }

    // MARK: - Eviction bookkeeping

    func testForgetRemovesOnlyTheNamedKey() {
        var lru = tracker([(.tiny, -100), (.base, -50), (.small, 0)])
        lru.forget(.tiny)

        XCTAssertEqual(lru.count, 2)
        XCTAssertEqual(lru.trackedKeys, [.base, .small])
        XCTAssertEqual(lru.leastRecentlyUsed(), .base, "eviction candidate advances after a forget")
    }

    func testForgetIsANoOpForAnUntrackedKey() {
        var lru = tracker([(.base, 0)])
        lru.forget(.largeTurbo)
        XCTAssertEqual(lru.trackedKeys, [.base])
    }

    func testRemoveAllClearsEverything() {
        var lru = tracker([(.tiny, -100), (.base, -50), (.small, 0)])
        lru.removeAll()

        XCTAssertEqual(lru.count, 0)
        XCTAssertNil(lru.leastRecentlyUsed())
    }

    // MARK: - clearExceptMostRecent policy

    func testKeysToEvictKeepingMostRecentDropsAllButNewest() {
        let lru = tracker([(.tiny, -100), (.base, -50), (.small, 0)])
        XCTAssertEqual(Set(lru.keysToEvictKeepingMostRecent()), [.tiny, .base],
                       "only the most recently used model survives")
    }

    func testKeysToEvictKeepingMostRecentIsEmptyForSingleEntry() {
        let lru = tracker([(.base, 0)])
        XCTAssertTrue(lru.keysToEvictKeepingMostRecent().isEmpty)
    }

    func testKeysToEvictKeepingMostRecentIsEmptyWhenEmpty() {
        let lru = LRUAccessTracker<WhisperModel>()
        XCTAssertTrue(lru.keysToEvictKeepingMostRecent().isEmpty)
    }

    // MARK: - Repeated eviction converges

    /// Drives the same sequence the cache does when it exceeds `maxCached`:
    /// evict the LRU entry, forget it, repeat. Guards against an eviction loop
    /// that fails to shrink the tracker.
    func testRepeatedEvictionRemovesEntriesOldestFirst() {
        var lru = tracker([(.tiny, -300), (.base, -200), (.small, -100), (.largeTurbo, 0)])
        var evicted: [WhisperModel] = []

        while lru.count > 1 {
            guard let oldest = lru.leastRecentlyUsed() else { break }
            evicted.append(oldest)
            lru.forget(oldest)
        }

        XCTAssertEqual(evicted, [.tiny, .base, .small])
        XCTAssertEqual(lru.trackedKeys, [.largeTurbo])
    }
}
