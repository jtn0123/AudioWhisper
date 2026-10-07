import SwiftData
import XCTest
@testable import AudioWhisper

@MainActor
final class HistoryMaintenanceTests: IsolatedXCTestCase {
    private func container(count: Int) throws -> ModelContainer {
        let container = try ModelContainer(
            for: TranscriptionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        for index in 0..<count {
            let record = TranscriptionRecord(text: "Fixture \(index)", provider: .local, duration: 2,
                                             wordCount: 7, characterCount: 19)
            record.date = Date().addingTimeInterval(-Double(index))
            context.insert(record)
        }
        try context.save()
        return container
    }

    func testCancelledPageReadDoesNotFetchOrCallItsConsumer() async throws {
        let manager = DataManager(modelContainer: try container(count: 51))
        var consumed = 0
        let reading = Task { try await manager.forEachRecordPage(pageSize: 20) { consumed += $0.count } }
        reading.cancel()
        do { try await reading.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        XCTAssertEqual(consumed, 0)
    }

    func testBackgroundAggregationPreservesStoredCountsAcrossPages() async throws {
        let manager = DataManager(modelContainer: try container(count: 1001))
        let store = UsageMetricsStore(defaults: AppDefaults.defaults)
        store.reset()
        var pages: [Int] = []
        try await store.rebuildFromHistory(dataManager: manager) { count in
            await MainActor.run { pages.append(count) }
        }
        XCTAssertEqual(pages, [500, 1000, 1001])
        XCTAssertEqual(store.snapshot.totalSessions, 1001)
        XCTAssertEqual(store.snapshot.totalWords, 7007)
        XCTAssertEqual(store.snapshot.totalCharacters, 19019, "Use stored character counts, not text length")
        XCTAssertEqual(store.snapshot.totalDuration, 2002)
        XCTAssertEqual(store.snapshot.dailyActivity.values.reduce(0, +), 7007)
    }

    func testCancelledRecalculationPreservesLiveTotalsAndAllowsUIWork() async throws {
        let manager = DataManager(modelContainer: try container(count: 1001))
        let store = UsageMetricsStore(defaults: AppDefaults.defaults)
        store.reset()
        store.recordSession(duration: 3, wordCount: 4, characterCount: 5)
        let before = store.snapshot
        let entered = expectation(description: "First background page")
        var pages: [Int] = []
        let calculating = Task {
            try await store.rebuildFromHistory(dataManager: manager) { count in
                await MainActor.run { pages.append(count); entered.fulfill() }
                try? await Task.sleep(for: .seconds(10))
            }
        }
        await fulfillment(of: [entered], timeout: 3)
        // UI actor is free while the background operation remains in progress.
        XCTAssertEqual(pages, [500])
        calculating.cancel()
        do { try await calculating.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        XCTAssertEqual(store.snapshot, before)
    }

    func testRecalculationRejectsConcurrentHistoryAndUsageChanges() async throws {
        for changeHistory in [false, true] {
            let manager = DataManager(modelContainer: try container(count: 2))
            let store = UsageMetricsStore(defaults: AppDefaults.defaults)
            store.reset()
            var expected = store.snapshot
            do {
                try await store.rebuildFromHistory(dataManager: manager) { _ in
                    await MainActor.run {
                        if changeHistory { manager.historyRevision.advance() } else {
                            store.recordSession(duration: 3, wordCount: 4, characterCount: 5)
                        }
                        expected = store.snapshot
                    }
                }
                XCTFail("A stale scan must not overwrite a newer state")
            } catch HistoryMaintenanceError.libraryChanged {}
            XCTAssertEqual(store.snapshot, expected)
        }
    }

    func testBatchRetentionKeepsCutoffBoundaryAndPublishesRevisionOnlyForDeletion() async throws {
        let container = try container(count: 0)
        let context = ModelContext(container)
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        for index in 0..<1001 {
            let record = TranscriptionRecord(text: "Expired \(index)", provider: .local)
            record.date = cutoff.addingTimeInterval(-100)
            context.insert(record)
        }
        let boundary = TranscriptionRecord(text: "Boundary", provider: .local)
        boundary.date = cutoff
        context.insert(boundary)
        let recent = TranscriptionRecord(text: "Recent", provider: .local)
        context.insert(recent)
        try context.save()
        let count = try await HistoryMaintenance.deleteExpired(container: container, before: cutoff)
        XCTAssertEqual(count, 1001)
        let manager = DataManager(modelContainer: container)
        var records = try await manager.fetchAllRecords()
        XCTAssertEqual(Set(records.map(\.text)), ["Boundary", "Recent"])
        manager.retentionPeriod = .oneWeek
        let revision = manager.historyRevision.value
        try await manager.cleanupExpiredRecords()
        XCTAssertEqual(manager.historyRevision.value, revision + 1, "Boundary ages past the live cutoff")
        try await manager.cleanupExpiredRecords()
        XCTAssertEqual(manager.historyRevision.value, revision + 1, "No mutation must not invalidate the Library")
        records = try await manager.fetchAllRecords()
        XCTAssertEqual(records.map(\.text), ["Recent"])
    }

    func testCancelledRetentionLeavesAllRecordsIntact() async throws {
        let container = try container(count: 3)
        let deleting = Task {
            try await HistoryMaintenance.deleteExpired(container: container, before: Date().addingTimeInterval(1))
        }
        deleting.cancel()
        do { _ = try await deleting.value; XCTFail("Expected cancellation") } catch is CancellationError {}
        let records = try await DataManager(modelContainer: container).fetchAllRecords()
        XCTAssertEqual(records.count, 3)
    }

    func testBackgroundBootstrapCanRebuildOnlyDailyActivityWithoutResettingLiveTotals() async throws {
        let manager = DataManager(modelContainer: try container(count: 2))
        AppDefaults.transcriptionHistoryEnabled = true
        let store = UsageMetricsStore(defaults: AppDefaults.defaults)
        var base = UsageSnapshot.empty
        base.totalSessions = 40
        base.totalWords = 400
        base.totalDuration = 60
        store.setSnapshotForTesting(base)
        await store.bootstrapIfNeeded(dataManager: manager)
        XCTAssertEqual(store.snapshot.totalSessions, 40)
        XCTAssertEqual(store.snapshot.totalWords, 400)
        XCTAssertEqual(store.snapshot.totalDuration, 60)
        XCTAssertEqual(store.snapshot.dailyActivity.values.reduce(0, +), 14)
    }

    func testEmptyBackgroundBootstrapDoesNotInventUsage() async throws {
        AppDefaults.transcriptionHistoryEnabled = true
        let manager = DataManager(modelContainer: try container(count: 0))
        let store = UsageMetricsStore(defaults: AppDefaults.defaults)
        store.reset()
        await store.bootstrapIfNeeded(dataManager: manager)
        XCTAssertEqual(store.snapshot, .empty)
    }
}
