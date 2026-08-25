import Foundation
import os.log
import SwiftData

// MARK: - Reads

/// Fetch and paging operations, split out of `DataManager.swift`.
///
/// The split is mechanical, not architectural: adding `forEachRecordPage` and
/// `fetchRecordsQuietly` for audit item B1/G2 pushed the class body past
/// SwiftLint's `type_body_length` limit of 250 lines. The reads form the
/// natural seam — they share no mutable state with the write/delete/retention
/// paths beyond `modelContainer`.
extension DataManager {
    func fetchAllRecords() async throws -> [TranscriptionRecord] {
        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }

        do {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TranscriptionRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let records = try context.fetch(descriptor)

            Logger.dataManager.debug("Fetched \(records.count) transcription records")
            return records

        } catch {
            Logger.dataManager.error("Failed to fetch transcription records: \(error.localizedDescription)")
            throw DataManagerError.fetchFailed(error)
        }
    }

    /// See `DataManagerProtocol.forEachRecordPage(pageSize:_:)`.
    ///
    /// Uses `fetchLimit` + `fetchOffset` on a stable `date`-descending sort. A
    /// concurrent insert during iteration can shift the window, which is
    /// acceptable here: every caller is computing approximate running totals
    /// for display, not a transactional report.
    func forEachRecordPage(
        pageSize: Int,
        _ body: ([TranscriptionRecord]) -> Void
    ) async throws {
        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }
        guard pageSize > 0 else { return }

        let context = ModelContext(container)
        var offset = 0
        while true {
            var descriptor = FetchDescriptor<TranscriptionRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset

            let page = try context.fetch(descriptor)
            if page.isEmpty { break }
            body(page)
            if page.count < pageSize { break }
            offset += pageSize
        }
    }

    func fetchRecords(matching searchQuery: String) async throws -> [TranscriptionRecord] {
        // Backward compatibility - calls the new method with no pagination
        return try await fetchRecords(matching: searchQuery, limit: nil, offset: nil)
    }

    func fetchRecords(matching searchQuery: String, limit: Int? = nil, offset: Int? = nil) async throws -> [TranscriptionRecord] {
        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }

        do {
            let context = ModelContext(container)
            var descriptor: FetchDescriptor<TranscriptionRecord>

            if searchQuery.isEmpty {
                // If no search query, return all records
                descriptor = FetchDescriptor<TranscriptionRecord>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            } else {
                // `localizedStandardContains` is already case-insensitive, so
                // no manual `.lowercased()` is needed (bug #49).
                let predicate = #Predicate<TranscriptionRecord> { record in
                    record.text.localizedStandardContains(searchQuery) ||
                    record.provider.localizedStandardContains(searchQuery) ||
                    (record.modelUsed?.localizedStandardContains(searchQuery) ?? false)
                }

                descriptor = FetchDescriptor<TranscriptionRecord>(
                    predicate: predicate,
                    sortBy: [SortDescriptor(\.date, order: .reverse)]
                )
            }

            // Apply pagination if specified
            if let limit = limit {
                descriptor.fetchLimit = limit
            }
            if let offset = offset {
                descriptor.fetchOffset = offset
            }

            let records = try context.fetch(descriptor)

            Logger.dataManager.debug("Fetched \(records.count) records matching query: '\(searchQuery)' (limit: \(limit ?? -1), offset: \(offset ?? 0))")
            return records

        } catch {
            Logger.dataManager.error("Failed to fetch transcription records: \(error.localizedDescription)")
            throw DataManagerError.fetchFailed(error)
        }
    }

    func fetchRecords(limit: Int, offset: Int, search: String?) async throws -> [TranscriptionRecord] {
        guard let container = modelContainer else {
            throw DataManagerError.modelContainerUnavailable
        }

        do {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<TranscriptionRecord>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            descriptor.fetchOffset = offset

            if let term = search, !term.isEmpty {
                // `localizedStandardContains` is already case-insensitive (bug #49).
                descriptor.predicate = #Predicate<TranscriptionRecord> { record in
                    record.text.localizedStandardContains(term)
                }
            }

            let records = try context.fetch(descriptor)
            Logger.dataManager.debug("Paginated fetch: \(records.count) records (limit: \(limit), offset: \(offset), search: '\(search ?? "")')")
            return records
        } catch {
            Logger.dataManager.error("Failed to paginate transcription records: \(error.localizedDescription)")
            throw DataManagerError.fetchFailed(error)
        }
    }
}
