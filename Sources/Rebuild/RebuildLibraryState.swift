import Foundation
import Observation

/// Library requests and expansion state have one observable owner. The view
/// schedules requests; this owner checks cancellation, search and revision
/// before publishing them, including when tested without a native window.
@MainActor
@Observable
final class RebuildLibraryState {
    let history: DataManagerProtocol
    private(set) var records: [TranscriptionRecord] = []
    var search = ""
    var error: String?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var hasMore = false
    var expanded: Set<UUID> = []
    var showingOriginal: Set<UUID> = []

    init(history: DataManagerProtocol) { self.history = history }

    func load(reset: Bool, enabled: Bool) async {
        guard enabled else {
            records = []
            expanded = []
            showingOriginal = []
            return
        }
        loading = true
        defer { loading = false }
        let query = search
        let revision = history.historyRevision.value
        do {
            let page = try await history.fetchRecords(limit: 50, offset: reset ? 0 : records.count, search: query)
            guard !Task.isCancelled, query == search, revision == history.historyRevision.value else { return }
            records = reset ? page : records + page
            hasMore = page.count == 50
            let visible = Set(records.map(\.id))
            expanded.formIntersection(visible)
            showingOriginal.formIntersection(visible)
            error = nil
            loaded = true
        } catch {
            guard !Task.isCancelled, query == search, revision == history.historyRevision.value else { return }
            self.error = error.localizedDescription
            loaded = true
        }
    }
}
