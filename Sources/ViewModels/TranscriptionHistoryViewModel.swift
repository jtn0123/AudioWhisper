import Foundation

/// ViewModel for `TranscriptionHistoryView`. Owns the paged record data, the
/// load/pagination state, and all `DataManager` interactions so the view never
/// touches the store directly (audit item A2).
///
/// `dataManager` is injected via the initializer with a `DataManager.shared`
/// default, mirroring `DashboardHomeView`'s constructor injection so tests can
/// substitute a `MockDataManager`.
@MainActor
@Observable
final class TranscriptionHistoryViewModel {
    // MARK: - Data + Load State

    private(set) var records: [TranscriptionRecord] = []
    private(set) var page: Int = 0
    private(set) var hasMore: Bool = true
    private(set) var isLoading: Bool = false
    private(set) var hasLoadedOnce: Bool = false

    var showError = false
    var errorMessage = ""

    // MARK: - Dependencies

    private let dataManager: DataManagerProtocol
    private let pageSize: Int

    // MARK: - Initialization

    init(dataManager: DataManagerProtocol = DataManager.shared, pageSize: Int = 50) {
        self.dataManager = dataManager
        self.pageSize = pageSize
    }

    // MARK: - Paginated Loading

    /// Loads the next page of records (or the first page when `reset` is true).
    /// `search` is the raw search text from the view; it is trimmed here and
    /// treated as "no filter" when empty.
    func loadRecords(reset: Bool = false, search: String = "") async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        if reset {
            page = 0
            hasMore = true
        }

        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchTerm: String? = trimmed.isEmpty ? nil : trimmed

        do {
            let offset = page * pageSize
            let batch = try await dataManager.fetchRecords(
                limit: pageSize,
                offset: offset,
                search: searchTerm
            )

            if reset {
                records = batch
            } else {
                records.append(contentsOf: batch)
            }

            // A short batch means we hit the end. Also treat an empty batch as
            // "no more" so an exact multiple of `pageSize` doesn't leave
            // `hasMore` true and trigger one wasted empty fetch (bug #43).
            hasMore = !batch.isEmpty && batch.count == pageSize
            page += 1
        } catch {
            errorMessage = "Failed to load transcription history: \(error.localizedDescription)"
            showError = true
            hasMore = false
        }
    }

    // MARK: - Mutations

    /// Deletes a single record and reloads the first page on success.
    func deleteRecord(_ record: TranscriptionRecord, search: String = "") async {
        do {
            try await dataManager.deleteRecord(record)
            await loadRecords(reset: true, search: search)
        } catch {
            errorMessage = "Failed to delete record: \(error.localizedDescription)"
            showError = true
        }
    }

    /// Deletes every record and reloads the first page.
    func clearAllRecords(search: String = "") async {
        isLoading = true
        do {
            try await dataManager.deleteAllRecords()
        } catch {
            errorMessage = "Failed to clear all records: \(error.localizedDescription)"
            showError = true
        }
        isLoading = false
        await loadRecords(reset: true, search: search)
    }
}
