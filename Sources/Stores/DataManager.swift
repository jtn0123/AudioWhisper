import Foundation
import SwiftData
import os.log

internal enum DataManagerError: Error, LocalizedError {
    case initializationFailed(Error)
    case saveFailed(Error)
    case fetchFailed(Error)
    case deleteFailed(Error)
    case cleanupFailed(Error)
    case modelContainerUnavailable

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let error):
            return "Failed to initialize data storage: \(error.localizedDescription)"
        case .saveFailed(let error):
            return "Failed to save transcription record: \(error.localizedDescription)"
        case .fetchFailed(let error):
            return "Failed to fetch transcription records: \(error.localizedDescription)"
        case .deleteFailed(let error):
            return "Failed to delete transcription record: \(error.localizedDescription)"
        case .cleanupFailed(let error):
            return "Failed to clean up old records: \(error.localizedDescription)"
        case .modelContainerUnavailable:
            return "Data storage is not available"
        }
    }
}

internal enum RetentionPeriod: String, CaseIterable, Codable {
    case oneWeek
    case oneMonth
    case threeMonths
    case forever

    var displayName: String {
        switch self {
        case .oneWeek:
            return "1 Week"
        case .oneMonth:
            return "1 Month"
        case .threeMonths:
            return "3 Months"
        case .forever:
            return "Forever"
        }
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .oneWeek:
            return 7 * 24 * 60 * 60 // 7 days in seconds
        case .oneMonth:
            return 30 * 24 * 60 * 60 // 30 days in seconds
        case .threeMonths:
            return 90 * 24 * 60 * 60 // 90 days in seconds
        case .forever:
            return nil
        }
    }
}

@MainActor
internal protocol DataManagerProtocol {
    var isHistoryEnabled: Bool { get }
    var retentionPeriod: RetentionPeriod { get set }
    var sharedModelContainer: ModelContainer? { get }

    func initialize() throws
    func saveTranscription(_ record: TranscriptionRecord) async throws
    /// Fetches every record. Reserved for export / counter-rebuild flows; list
    /// views should use `fetchRecords(limit:offset:search:)` to avoid loading
    /// the whole history into memory.
    func fetchAllRecords() async throws -> [TranscriptionRecord]
    /// Streams every record to `body` in pages of `pageSize`, newest first.
    ///
    /// Audit item B1/G2: aggregate callers (usage-metric rebuilds, dashboard
    /// provider stats) previously went through `fetchAllRecords()`, which
    /// materialises the entire table. Retention is user-configurable and one
    /// option is *forever*, so that grows without bound. Paging keeps peak
    /// memory at one page regardless of history size while producing the same
    /// totals.
    func forEachRecordPage(
        pageSize: Int,
        _ body: ([TranscriptionRecord]) -> Void
    ) async throws
    func fetchRecords(matching searchQuery: String) async throws -> [TranscriptionRecord]
    func fetchRecords(matching searchQuery: String, limit: Int?, offset: Int?) async throws -> [TranscriptionRecord]
    /// Fetches a paginated, optionally search-filtered slice of records, sorted
    /// by date descending. Use this from list views. `fetchAllRecords()` is
    /// reserved for export / counter rebuild flows.
    ///
    /// - Parameters:
    ///   - limit: Max records to return.
    ///   - offset: Number of records to skip (for paging).
    ///   - search: Case-insensitive substring filter over the transcript text;
    ///             `nil` or empty disables filtering.
    func fetchRecords(limit: Int, offset: Int, search: String?) async throws -> [TranscriptionRecord]
    func deleteRecord(_ record: TranscriptionRecord) async throws
    func deleteAllRecords() async throws
    func cleanupExpiredRecords() async throws

    // Backward compatibility methods that don't throw
    func saveTranscriptionQuietly(_ record: TranscriptionRecord) async
    func fetchAllRecordsQuietly() async -> [TranscriptionRecord]
    /// Non-throwing bounded fetch. Audit item B1/G2: list surfaces that show a
    /// fixed number of rows should use this rather than `fetchAllRecordsQuietly()`.
    func fetchRecordsQuietly(limit: Int, offset: Int, search: String?) async -> [TranscriptionRecord]
    func cleanupExpiredRecordsQuietly() async
}

@MainActor
internal final class DataManager: DataManagerProtocol {
    nonisolated(unsafe) static let shared: DataManagerProtocol = MainActor.assumeIsolated {
        DataManager()
    }

    /// Not `private` because the read/paging operations live in the
    /// `DataManager+Fetching.swift` extension, and `private` is file-scoped.
    var modelContainer: ModelContainer?

    /// Tracks the single in-flight retention-cleanup task. Back-to-back saves
    /// reuse / skip rather than each spawning an unbounded task (bug #17).
    private var cleanupTask: Task<Void, Never>?

    /// Public accessor for the model container, primarily for SwiftUI integration
    var sharedModelContainer: ModelContainer? {
        return modelContainer
    }

    var isHistoryEnabled: Bool {
        return AppDefaults.transcriptionHistoryEnabled
    }

    var retentionPeriod: RetentionPeriod {
        get { AppDefaults.transcriptionRetentionPeriod }
        set { AppDefaults.transcriptionRetentionPeriod = newValue }
    }

    private init() {}

    /// Builds an instance backed by an explicit container, for tests.
    ///
    /// Audit item B1/G2: `forEachRecordPage` is real SwiftData paging
    /// (`fetchLimit` + `fetchOffset` against a live store), and the only honest
    /// way to test it is against a real `ModelContainer`. Every existing
    /// DataManager test uses `MockDataManager`, which would just be testing the
    /// mock's own array slicing. `init()` stays private so production code
    /// still goes through `.shared`.
    ///
    /// Pass an in-memory configuration — this must never touch the user's store.
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func initialize() throws {
        do {
            let schema = Schema([
                TranscriptionRecord.self
            ])

            try RebuildStorage.prepare()
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                url: RebuildStorage.history,
                allowsSave: true
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )

            // Perform initial cleanup of expired records
            Task {
                await cleanupExpiredRecordsQuietly()
            }

        } catch {
            Logger.dataManager.error("Failed to initialize DataManager: \(error.localizedDescription)")
            throw DataManagerError.initializationFailed(error)
        }
    }

    func saveTranscription(_ record: TranscriptionRecord) async throws {
        guard isHistoryEnabled else {
            Logger.dataManager.debug("Transcription history is disabled, skipping save")
            return
        }

        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }

        do {
            let context = ModelContext(container)
            context.insert(record)
            try context.save()

            Logger.dataManager.info("Saved transcription record with ID: \(record.id)")

            // Retention cleanup runs off the save critical path — the caller
            // (and the UI) shouldn't wait on a full predicate fetch + delete.
            // Coalesce back-to-back saves into a single in-flight task instead
            // of spawning an unbounded, untracked task per save (bug #17).
            scheduleCleanup()

        } catch {
            Logger.dataManager.error("Failed to save transcription record: \(error.localizedDescription)")
            throw DataManagerError.saveFailed(error)
        }
    }

    /// Schedules a retention cleanup, coalescing concurrent requests: if a
    /// cleanup task is already in flight, this is a no-op so back-to-back saves
    /// don't each spawn a task (bug #17).
    private func scheduleCleanup() {
        if let cleanupTask, !cleanupTask.isCancelled {
            return
        }
        cleanupTask = Task { [weak self] in
            await self?.cleanupExpiredRecordsQuietly()
            self?.cleanupTask = nil
        }
    }

    func deleteRecord(_ record: TranscriptionRecord) async throws {
        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }

        do {
            let context = ModelContext(container)

            // Use predicate to find specific record instead of fetching all
            let targetId = record.id
            var descriptor = FetchDescriptor<TranscriptionRecord>(
                predicate: #Predicate { $0.id == targetId }
            )
            descriptor.fetchLimit = 1

            let matches = try context.fetch(descriptor)
            guard let recordToDelete = matches.first else {
                Logger.dataManager.warning("Record with ID \(record.id) not found for deletion")
                return
            }

            context.delete(recordToDelete)
            try context.save()

            Logger.dataManager.info("Deleted transcription record with ID: \(record.id)")

        } catch {
            Logger.dataManager.error("Failed to delete transcription record: \(error.localizedDescription)")
            throw DataManagerError.deleteFailed(error)
        }

        // B5/G2: subtract this record's contribution instead of fetching every
        // remaining record to recompute totals from scratch. The previous
        // rebuild meant deleting a single transcript cost a full-table load on
        // the main actor, scaling with total history — the one unbounded fetch
        // in an otherwise carefully paginated data layer.
        //
        // This runs after the delete has committed, and is best-effort: it must
        // never turn a successful delete into a reported failure (bug #19).
        UsageMetricsStore.shared.remove(record: record)
        SourceUsageStore.shared.remove(record: record)
    }

    func deleteAllRecords() async throws {
        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }

        do {
            let context = ModelContext(container)

            // B5/G2: batch delete rather than fetching every record and deleting
            // them one at a time. The old path materialised the entire history
            // in memory purely to throw it away.
            try context.delete(model: TranscriptionRecord.self)
            try context.save()

            Logger.dataManager.info("Deleted all transcription records")

            // Reset usage metrics and source stats since all records are gone
            UsageMetricsStore.shared.reset()
            SourceUsageStore.shared.reset()

        } catch {
            Logger.dataManager.error("Failed to delete all transcription records: \(error.localizedDescription)")
            throw DataManagerError.deleteFailed(error)
        }
    }

    func cleanupExpiredRecords() async throws {
        guard let cutoffDate = RetentionPolicy.cutoffDate(for: retentionPeriod) else {
            Logger.dataManager.debug("Retention period is forever, no cleanup needed")
            return
        }

        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }

        do {
            let context = ModelContext(container)

            // Use SwiftData predicate for database-level filtering
            let predicate = #Predicate<TranscriptionRecord> { record in
                record.date < cutoffDate
            }

            let descriptor = FetchDescriptor<TranscriptionRecord>(predicate: predicate)
            let expiredRecords = try context.fetch(descriptor)

            for record in expiredRecords {
                context.delete(record)
            }

            try context.save()

            if !expiredRecords.isEmpty {
                Logger.dataManager.info("Cleaned up \(expiredRecords.count) expired transcription records")
            }

        } catch {
            Logger.dataManager.error("Failed to cleanup expired records: \(error.localizedDescription)")
            throw DataManagerError.cleanupFailed(error)
        }
    }

    // MARK: - Backward Compatibility Methods

    func saveTranscriptionQuietly(_ record: TranscriptionRecord) async {
        do {
            try await saveTranscription(record)
        } catch {
            Logger.dataManager.error("DataManager operation failed: \(error.localizedDescription)")
        }
    }

    func fetchAllRecordsQuietly() async -> [TranscriptionRecord] {
        do {
            return try await fetchAllRecords()
        } catch {
            Logger.dataManager.error("DataManager operation failed: \(error.localizedDescription)")
            return []
        }
    }

    func fetchRecordsQuietly(limit: Int, offset: Int, search: String?) async -> [TranscriptionRecord] {
        do {
            return try await fetchRecords(limit: limit, offset: offset, search: search)
        } catch {
            Logger.dataManager.error("DataManager operation failed: \(error.localizedDescription)")
            return []
        }
    }

    func cleanupExpiredRecordsQuietly() async {
        do {
            try await cleanupExpiredRecords()
        } catch {
            Logger.dataManager.error("DataManager operation failed: \(error.localizedDescription)")
        }
    }
}
