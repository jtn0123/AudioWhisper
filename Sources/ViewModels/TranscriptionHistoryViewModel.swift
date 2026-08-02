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

    /// Tracks the in-flight load Task so a new `loadRecords` call can cancel
    /// the previous one instead of being silently dropped (bugs H13/H14).
    /// Updated only on the MainActor, so no extra synchronization is needed.
    private var currentLoadTask: Task<Void, Never>?

    /// Debounce in nanoseconds applied to search-driven reloads to avoid one
    /// Task per keystroke. 200ms matches the "feels responsive but not
    /// thrashing" target from the bug report.
    private static let searchDebounceNanos: UInt64 = 200_000_000

    // MARK: - Initialization

    init(dataManager: DataManagerProtocol = DataManager.shared, pageSize: Int = 50) {
        self.dataManager = dataManager
        self.pageSize = pageSize
    }

    // MARK: - Paginated Loading

    /// Loads the next page of records (or the first page when `reset` is true).
    /// `search` is the raw search text from the view; it is trimmed here and
    /// treated as "no filter" when empty.
    ///
    /// Replaces the old `guard !isLoading else { return }` pattern, which
    /// silently dropped keystrokes while a previous load was in flight (bugs
    /// H13/H14). The latest call now wins: it cancels any in-flight load,
    /// then debounces briefly (when `reset` is true) so per-keystroke search
    /// doesn't spawn a Task per character.
    func loadRecords(reset: Bool = false, search: String = "") async {
        // Cancel any in-flight load and replace it. The new task wins; the
        // old one will observe cancellation and exit early.
        currentLoadTask?.cancel()

        // Reflect "loading" immediately so the UI shows the spinner while we
        // wait through the debounce window. Doing it here (instead of inside
        // the Task) prevents brief `isLoading = false` flicker when the
        // cancelled task's defer fires after the new task has been queued.
        isLoading = true

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(reset: reset, search: search)
        }
        currentLoadTask = task
        await task.value
    }

    private func performLoad(reset: Bool, search: String) async {
        // Debounce reset/search loads only — paginated "load more" calls
        // shouldn't be delayed. `Task.sleep` throws on cancellation, which
        // is exactly the early-exit we want.
        if reset {
            do {
                try await Task.sleep(nanoseconds: Self.searchDebounceNanos)
            } catch {
                return
            }
        }

        if Task.isCancelled { return }

        // Only the latest task is responsible for clearing `isLoading`.
        // Stale (cancelled) tasks bail out without touching shared state so
        // they can't flip the spinner off while a newer load is still going.
        defer {
            if !Task.isCancelled {
                isLoading = false
                hasLoadedOnce = true
            }
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

            if Task.isCancelled { return }

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
            if Task.isCancelled { return }
            errorMessage = LocalizedStrings.Errors.historyLoadFailed
                .substitutingPlaceholder(error.localizedDescription)
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
            errorMessage = LocalizedStrings.Errors.historyDeleteFailed
                .substitutingPlaceholder(error.localizedDescription)
            showError = true
        }
    }

    /// Deletes every record and reloads the first page.
    func clearAllRecords(search: String = "") async {
        isLoading = true
        do {
            try await dataManager.deleteAllRecords()
        } catch {
            errorMessage = LocalizedStrings.Errors.historyClearFailed
                .substitutingPlaceholder(error.localizedDescription)
            showError = true
        }
        isLoading = false
        await loadRecords(reset: true, search: search)
    }
}
