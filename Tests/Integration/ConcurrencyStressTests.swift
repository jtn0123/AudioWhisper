import XCTest
import SwiftData
@testable import AudioWhisper

/// Stress tests for concurrent operations across key components.
/// These tests verify thread safety and race condition handling.
final class ConcurrencyStressTests: XCTestCase {

    // MARK: - Concurrent Cache Access Tests

    func testConcurrentCacheReadsAreSafe() async {
        let cache = ConcurrentTestCache<String, Int>()

        // Pre-populate cache
        await cache.set("key1", value: 100)
        await cache.set("key2", value: 200)
        await cache.set("key3", value: 300)

        // Concurrent reads from multiple tasks
        await withTaskGroup(of: Int?.self) { group in
            for _ in 0..<100 {
                group.addTask { await cache.get("key1") }
                group.addTask { await cache.get("key2") }
                group.addTask { await cache.get("key3") }
            }

            var results: [Int] = []
            for await result in group {
                if let value = result {
                    results.append(value)
                }
            }

            XCTAssertEqual(results.count, 300, "All reads should succeed")
        }
    }

    func testConcurrentCacheWritesAreSafe() async {
        let cache = ConcurrentTestCache<String, Int>()

        // Concurrent writes from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    await cache.set("key-\(i)", value: i)
                }
            }
        }

        // Verify all writes succeeded
        let count = await cache.count()
        XCTAssertEqual(count, 100, "All 100 keys should be written")
    }

    func testConcurrentReadWriteMix() async {
        let cache = ConcurrentTestCache<String, Int>()

        // Pre-populate with some data
        for i in 0..<10 {
            await cache.set("key-\(i)", value: i)
        }

        // Mix of reads and writes concurrently
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for i in 10..<50 {
                group.addTask {
                    await cache.set("key-\(i)", value: i)
                }
            }

            // Readers
            for i in 0..<10 {
                group.addTask {
                    _ = await cache.get("key-\(i)")
                }
            }

            // Updaters (read then write)
            for i in 0..<10 {
                group.addTask {
                    if let value = await cache.get("key-\(i)") {
                        await cache.set("key-\(i)", value: value * 2)
                    }
                }
            }
        }

        // Verify cache is still consistent
        let count = await cache.count()
        XCTAssertGreaterThanOrEqual(count, 10, "At least original keys should exist")
    }

    // MARK: - Concurrent UserDefaults Access Tests

    func testConcurrentUserDefaultsAccess() async {
        let suiteName = "ConcurrencyTest-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Concurrent writes to different keys
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    defaults.set(i, forKey: "key-\(i)")
                }
            }
        }

        // Verify all values
        for i in 0..<50 {
            XCTAssertEqual(defaults.integer(forKey: "key-\(i)"), i)
        }
    }

    // MARK: - Concurrent Dictionary Modification Tests

    func testConcurrentDictionaryUpdates() async {
        let store = ConcurrentDictStore()

        // Concurrent modifications to same key
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    await store.increment("counter")
                }
            }
        }

        let finalValue = await store.get("counter")
        XCTAssertEqual(finalValue, 100, "100 increments should result in 100")
    }

    // MARK: - Concurrent Request ID Generation Tests

    func testConcurrentUUIDGeneration() async {
        let collector = UUIDCollector()

        await withTaskGroup(of: String.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    UUID().uuidString
                }
            }

            for await uuid in group {
                await collector.insert(uuid)
            }
        }

        let count = await collector.count()
        XCTAssertEqual(count, 1000, "All UUIDs should be unique")
    }

    // MARK: - Concurrent Date Formatting Tests

    func testConcurrentDateFormattingIsSafe() async {
        // DateFormatter is not thread-safe, but our pattern should handle it
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let dates = (0..<100).map { i in
            Calendar.current.date(byAdding: .day, value: -i, to: Date())!
        }

        // Concurrent formatting
        await withTaskGroup(of: String.self) { group in
            for date in dates {
                group.addTask {
                    // Each task gets its own formatter to avoid race conditions
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    return formatter.string(from: date)
                }
            }

            var results: [String] = []
            for await result in group {
                results.append(result)
            }

            XCTAssertEqual(results.count, 100)
        }
    }

    // MARK: - Actor Isolation Tests

    func testActorIsolationPreventsRaces() async {
        let counter = AtomicCounter()

        // Many concurrent increments
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    await counter.increment()
                }
            }
        }

        let value = await counter.value
        XCTAssertEqual(value, 1000, "Actor isolation should prevent race conditions")
    }

    func testActorHandlesConcurrentAccessPatterns() async {
        let store = TestActorStore()

        // Pattern: concurrent reads while writing
        await withTaskGroup(of: Void.self) { group in
            // Background writer
            group.addTask {
                for i in 0..<100 {
                    await store.add(item: "item-\(i)")
                }
            }

            // Concurrent readers
            for _ in 0..<10 {
                group.addTask {
                    for _ in 0..<50 {
                        _ = await store.count()
                    }
                }
            }
        }

        let finalCount = await store.count()
        XCTAssertEqual(finalCount, 100, "All items should be added")
    }

    // MARK: - Cancellation Handling Tests

    func testTaskCancellationHandling() async {
        let completedTasks = AtomicCounter()

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    if i % 2 == 0 {
                        // Simulate some work
                        try? await Task.sleep(nanoseconds: 1_000_000)
                    }
                    await completedTasks.increment()
                }
            }

            // Let some tasks complete
            try? await Task.sleep(nanoseconds: 5_000_000)

            // Cancel remaining
            group.cancelAll()
        }

        // Some tasks should have completed
        let completed = await completedTasks.value
        XCTAssertGreaterThan(completed, 0, "At least some tasks should complete")
    }

    // MARK: - High Contention Tests

    func testHighContentionOnSingleKey() async {
        let store = ConcurrentDictStore()

        // All tasks compete for same key
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask {
                    await store.increment("hotkey")
                }
            }
        }

        let value = await store.get("hotkey")
        XCTAssertEqual(value, 500, "High contention should still be correct")
    }

    // MARK: - Memory Pressure Simulation

    func testConcurrentOperationsUnderLoad() async {
        let cache = ConcurrentTestCache<Int, [Float]>()

        // Create some memory pressure with large values
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    // 1000 floats = 4KB per entry
                    let data = [Float](repeating: Float(i), count: 1000)
                    await cache.set(i, value: data)
                }
            }
        }

        let count = await cache.count()
        XCTAssertEqual(count, 20)

        // Concurrent access and eviction simulation
        await withTaskGroup(of: Void.self) { group in
            // Readers
            for i in 0..<20 {
                group.addTask {
                    _ = await cache.get(i)
                }
            }

            // Eviction
            group.addTask {
                for i in 0..<10 {
                    await cache.remove(i)
                }
            }
        }
    }
}

// MARK: - Test Helper Actors

private actor ConcurrentTestCache<K: Hashable, V> {
    private var storage: [K: V] = [:]

    func get(_ key: K) -> V? {
        storage[key]
    }

    func set(_ key: K, value: V) {
        storage[key] = value
    }

    func remove(_ key: K) {
        storage.removeValue(forKey: key)
    }

    func count() -> Int {
        storage.count
    }
}

private actor ConcurrentDictStore {
    private var dict: [String: Int] = [:]

    func increment(_ key: String) {
        dict[key, default: 0] += 1
    }

    func get(_ key: String) -> Int {
        dict[key] ?? 0
    }
}

private actor AtomicCounter {
    private(set) var value: Int = 0

    func increment() {
        value += 1
    }
}

private actor TestActorStore {
    private var items: [String] = []

    func add(item: String) {
        items.append(item)
    }

    func count() -> Int {
        items.count
    }

    func getAll() -> [String] {
        items
    }
}

private actor UUIDCollector {
    private var uuids: Set<String> = []

    func insert(_ uuid: String) {
        uuids.insert(uuid)
    }

    func count() -> Int {
        uuids.count
    }
}
