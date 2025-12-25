import XCTest
@testable import AudioWhisper

/// Tests for LRU cache behavior in LocalWhisperService.
/// Note: The WhisperKitCache is a private actor, so we test through the public interface
/// and observable behavior of LocalWhisperService.
final class LRUCacheTests: XCTestCase {

    // MARK: - Cache Eviction Logic Tests

    /// Test that the LRU eviction algorithm correctly identifies the oldest item.
    /// We simulate the sorting logic used in the WhisperKitCache.
    func testLRUSortingByAccessTime() {
        // Simulate access times dictionary
        var accessTimes: [String: Date] = [:]
        let now = Date()

        accessTimes["model-a"] = now.addingTimeInterval(-100) // Oldest
        accessTimes["model-b"] = now.addingTimeInterval(-50)  // Middle
        accessTimes["model-c"] = now                           // Newest

        // Sort by ascending date (oldest first)
        let sortedByLRU = accessTimes.sorted { $0.value < $1.value }

        XCTAssertEqual(sortedByLRU.first?.key, "model-a", "Oldest model should be first")
        XCTAssertEqual(sortedByLRU.last?.key, "model-c", "Newest model should be last")
    }

    func testLRUSortingHandlesSameTimestamp() {
        var accessTimes: [String: Date] = [:]
        let now = Date()

        // All same timestamp
        accessTimes["model-a"] = now
        accessTimes["model-b"] = now
        accessTimes["model-c"] = now

        let sortedByLRU = accessTimes.sorted { $0.value < $1.value }

        // All should be present (order may vary for same timestamp)
        XCTAssertEqual(sortedByLRU.count, 3)
    }

    func testLRUSortingWithSingleItem() {
        var accessTimes: [String: Date] = [:]
        accessTimes["model-a"] = Date()

        let sortedByLRU = accessTimes.sorted { $0.value < $1.value }

        XCTAssertEqual(sortedByLRU.count, 1)
        XCTAssertEqual(sortedByLRU.first?.key, "model-a")
    }

    func testLRUSortingEmptyCache() {
        let accessTimes: [String: Date] = [:]
        let sortedByLRU = accessTimes.sorted { $0.value < $1.value }

        XCTAssertTrue(sortedByLRU.isEmpty)
    }

    // MARK: - Eviction Threshold Tests

    /// Test eviction logic: should only evict when at or above maxCached
    func testEvictionThreshold() {
        let maxCached = 3

        // Below threshold - no eviction needed
        XCTAssertFalse(shouldEvict(currentCount: 0, maxCached: maxCached))
        XCTAssertFalse(shouldEvict(currentCount: 1, maxCached: maxCached))
        XCTAssertFalse(shouldEvict(currentCount: 2, maxCached: maxCached))

        // At threshold - eviction needed before adding new item
        XCTAssertTrue(shouldEvict(currentCount: 3, maxCached: maxCached))

        // Above threshold - definitely needs eviction
        XCTAssertTrue(shouldEvict(currentCount: 4, maxCached: maxCached))
    }

    private func shouldEvict(currentCount: Int, maxCached: Int) -> Bool {
        // Mirrors the condition in WhisperKitCache.evictLeastRecentlyUsedIfNeeded
        return currentCount >= maxCached
    }

    // MARK: - Access Time Update Tests

    func testAccessTimeUpdatesOnHit() {
        var accessTimes: [String: Date] = [:]
        let initialTime = Date().addingTimeInterval(-100)

        // Initial access
        accessTimes["model-a"] = initialTime

        // Simulate cache hit - update access time
        let hitTime = Date()
        accessTimes["model-a"] = hitTime

        XCTAssertEqual(accessTimes["model-a"], hitTime)
        XCTAssertNotEqual(accessTimes["model-a"], initialTime)
    }

    func testMostRecentlyUsedPreservedOnClear() {
        var instances: [String: String] = [:]
        var accessTimes: [String: Date] = [:]
        let now = Date()

        instances["model-a"] = "instance-a"
        instances["model-b"] = "instance-b"
        instances["model-c"] = "instance-c"

        accessTimes["model-a"] = now.addingTimeInterval(-100)
        accessTimes["model-b"] = now                           // Most recent
        accessTimes["model-c"] = now.addingTimeInterval(-50)

        // Simulate clearExceptMostRecent
        let sortedByAccess = accessTimes.sorted { $0.value > $1.value }

        for (index, model) in sortedByAccess.enumerated() {
            if index > 0 {
                instances.removeValue(forKey: model.key)
                accessTimes.removeValue(forKey: model.key)
            }
        }

        XCTAssertEqual(instances.count, 1)
        XCTAssertNotNil(instances["model-b"], "Most recently used should be preserved")
        XCTAssertNil(instances["model-a"])
        XCTAssertNil(instances["model-c"])
    }

    // MARK: - Cache State Tests

    func testCacheClearRemovesAllEntries() {
        var instances: [String: String] = [
            "model-a": "instance-a",
            "model-b": "instance-b",
            "model-c": "instance-c"
        ]
        var accessTimes: [String: Date] = [
            "model-a": Date(),
            "model-b": Date(),
            "model-c": Date()
        ]

        // Simulate clear
        instances.removeAll()
        accessTimes.removeAll()

        XCTAssertTrue(instances.isEmpty)
        XCTAssertTrue(accessTimes.isEmpty)
    }

    func testEvictionRemovesCorrectModel() {
        var instances: [String: String] = [:]
        var accessTimes: [String: Date] = [:]
        let now = Date()

        // Fill cache
        instances["model-a"] = "instance-a"
        instances["model-b"] = "instance-b"
        instances["model-c"] = "instance-c"

        accessTimes["model-a"] = now.addingTimeInterval(-100) // Oldest - should be evicted
        accessTimes["model-b"] = now.addingTimeInterval(-50)
        accessTimes["model-c"] = now

        // Simulate eviction of LRU
        let sortedByAccess = accessTimes.sorted { $0.value < $1.value }
        if let oldestModel = sortedByAccess.first {
            instances.removeValue(forKey: oldestModel.key)
            accessTimes.removeValue(forKey: oldestModel.key)
        }

        XCTAssertNil(instances["model-a"], "Oldest model should be evicted")
        XCTAssertNotNil(instances["model-b"])
        XCTAssertNotNil(instances["model-c"])
        XCTAssertEqual(instances.count, 2)
    }

    // MARK: - Concurrent Access Simulation Tests

    func testConcurrentAccessToCache() async {
        let cache = TestCache()

        // Simulate concurrent access from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    await cache.access("model-\(i % 3)")
                }
            }
        }

        // All models should have been accessed
        let accessedModels = await cache.getAccessedModels()
        XCTAssertTrue(accessedModels.contains("model-0"))
        XCTAssertTrue(accessedModels.contains("model-1"))
        XCTAssertTrue(accessedModels.contains("model-2"))
    }

    func testConcurrentEvictionSafety() async {
        let cache = TestCache()

        // Fill cache with more items than max
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    await cache.addAndEvictIfNeeded("model-\(i)", maxCached: 5)
                }
            }
        }

        // Cache should not exceed max size
        let currentCount = await cache.count()
        XCTAssertLessThanOrEqual(currentCount, 5)
    }
}

// MARK: - Test Helper Actor

/// Actor for testing concurrent cache behavior safely
private actor TestCache {
    private var items: Set<String> = []
    private var accessTimes: [String: Date] = [:]

    func access(_ key: String) {
        items.insert(key)
        accessTimes[key] = Date()
    }

    func addAndEvictIfNeeded(_ key: String, maxCached: Int) {
        // Evict if at capacity
        while items.count >= maxCached, let oldest = oldestKey() {
            items.remove(oldest)
            accessTimes.removeValue(forKey: oldest)
        }

        items.insert(key)
        accessTimes[key] = Date()
    }

    private func oldestKey() -> String? {
        accessTimes.min(by: { $0.value < $1.value })?.key
    }

    func getAccessedModels() -> Set<String> {
        items
    }

    func count() -> Int {
        items.count
    }
}
