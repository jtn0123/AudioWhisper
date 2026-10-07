import Foundation
import Observation
import SwiftData

/// Library requests and expansion state have one observable owner. The view
/// schedules requests; this owner checks cancellation, search and revision
/// before publishing them, including when tested without a native window.
@MainActor
@Observable
final class RebuildLibraryState {
    typealias Export = (ModelContainer, URL, @escaping @Sendable (Int) async -> Void) async throws -> Int
    let history: DataManagerProtocol
    private(set) var records: [TranscriptionRecord] = []
    var search = ""
    var error: String?
    private(set) var loading = false
    private(set) var loaded = false
    private(set) var hasMore = false
    var expanded: Set<UUID> = []
    var showingOriginal: Set<UUID> = []
    var pendingDelete: TranscriptionRecord?
    var confirmDelete = false
    var confirmClear = false
    private(set) var exporting = false
    private(set) var exportedCount = 0
    private(set) var exportStatus: String?
    private let exporter: Export
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    init(history: DataManagerProtocol, exporter: @escaping Export = {
        try await HistoryExporter.export(container: $0, to: $1, progress: $2)
    }) {
        self.history = history
        self.exporter = exporter
    }

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

    func deletePending() async {
        guard !exporting, let record = pendingDelete else { return }
        defer { pendingDelete = nil }
        do {
            try await history.deleteRecord(record)
            await load(reset: true, enabled: AppDefaults.transcriptionHistoryEnabled)
        } catch { self.error = error.localizedDescription }
    }

    func clear() async {
        guard !exporting else { return }
        do {
            try await history.deleteAllRecords()
            await load(reset: true, enabled: AppDefaults.transcriptionHistoryEnabled)
        } catch { self.error = error.localizedDescription }
    }

    func startExport(to url: URL) {
        guard !exporting else { return }
        guard let container = history.sharedModelContainer else {
            error = "Your local library is unavailable. Try reopening the app."
            return
        }
        exporting = true
        exportedCount = 0
        exportStatus = nil
        error = nil
        exportTask = Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
                exporting = false
                exportTask = nil
            }
            do {
                let count = try await exporter(container, url) { count in
                    await MainActor.run { self.exportedCount = count }
                }
                exportStatus = "Exported \(count) transcripts."
            } catch is CancellationError {
                exportStatus = "Export cancelled. Your existing file was kept."
            } catch { self.error = error.localizedDescription }
        }
    }

    func cancelExport() { exportTask?.cancel() }
}
