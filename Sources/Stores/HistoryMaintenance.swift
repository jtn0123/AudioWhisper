import Foundation
import SwiftData

enum HistoryMaintenanceError: LocalizedError {
    case libraryChanged
    var errorDescription: String? { "History or usage changed during recalculation. Please try again." }
}

struct UsageHistoryScan: Sendable {
    let snapshot: UsageSnapshot
    let recordCount: Int
}

/// Contexts are created on the detached executor and never shared with UI
/// contexts. Only counts and value snapshots cross the actor boundary.
enum HistoryMaintenance {
    static func aggregate(
        container: ModelContainer, mode: UsageHistoryAccumulator.Mode,
        progress: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async throws -> UsageHistoryScan {
        let work = Task.detached(priority: .utility) {
            let worker = HistoryMaintenanceWorker(modelContainer: container)
            return try await worker.aggregate(mode: mode, progress: progress)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    static func deleteExpired(container: ModelContainer, before cutoff: Date) async throws -> Int {
        let work = Task.detached(priority: .utility) {
            let worker = HistoryMaintenanceWorker(modelContainer: container)
            return try await worker.deleteExpired(before: cutoff)
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
}

@ModelActor
private actor HistoryMaintenanceWorker {
    func aggregate(
        mode: UsageHistoryAccumulator.Mode, progress: @Sendable (Int) async -> Void
    ) async throws -> UsageHistoryScan {
        var accumulator = UsageHistoryAccumulator(mode: mode)
        while true {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<TranscriptionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 500
            descriptor.fetchOffset = accumulator.recordCount
            let page = try modelContext.fetch(descriptor)
            if page.isEmpty { break }
            for record in page {
                try Task.checkCancellation()
                accumulator.add(record)
            }
            await progress(accumulator.recordCount)
            if page.count < 500 { break }
        }
        try Task.checkCancellation()
        return UsageHistoryScan(snapshot: accumulator.finish(), recordCount: accumulator.recordCount)
    }

    func deleteExpired(before cutoff: Date) throws -> Int {
        try Task.checkCancellation()
        let predicate = #Predicate<TranscriptionRecord> { $0.date < cutoff }
        let count = try modelContext.fetchCount(FetchDescriptor<TranscriptionRecord>(predicate: predicate))
        guard count > 0 else { return 0 }
        try Task.checkCancellation()
        try modelContext.delete(model: TranscriptionRecord.self, where: predicate)
        try modelContext.save()
        // A committed deletion must be published even if cancellation arrives
        // after save; it cannot be represented as an uncommitted cancellation.
        return count
    }
}

/// One definition of the arithmetic for background scans and protocol-only
/// stores. Each scan owns its formatter; none is shared across executors.
struct UsageHistoryAccumulator {
    enum Mode: Sendable {
        case full
        case dailyActivityOnly(base: UsageSnapshot)
    }
    private let mode: Mode
    private var snapshot: UsageSnapshot
    private let formatter: DateFormatter
    private(set) var recordCount = 0

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .full: snapshot = .empty
        case .dailyActivityOnly(let base): snapshot = base; snapshot.dailyActivity = [:]
        }
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
    }

    mutating func add(_ record: TranscriptionRecord) {
        recordCount += 1
        if case .full = mode {
            snapshot.totalSessions += 1
            snapshot.totalDuration += record.duration ?? 0
            snapshot.totalWords += record.wordCount
            snapshot.totalCharacters += record.characterCount
        }
        snapshot.dailyActivity[formatter.string(from: record.date), default: 0] += record.wordCount
    }

    func finish() -> UsageSnapshot {
        var result = snapshot
        if case .full = mode { result.lastUpdated = Date() }
        return result
    }
}
