import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RebuildLibraryView: View {
    let history: DataManagerProtocol

    init(history: DataManagerProtocol = DataManager.shared) {
        self.history = history
    }

    private struct LoadRequest: Hashable {
        let search: String
        let enabled: Bool
        let revision: UInt64
    }
    @AppDefault(\.transcriptionHistoryEnabled) private var historyEnabled
    @State private var records: [TranscriptionRecord] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loading = false
    @State private var hasMore = false
    @State private var pendingDelete: TranscriptionRecord?
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var exportedCount = 0
    @State private var exportStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RebuildPageHeading(
                title: "Keep the useful words.",
                subtitle: "A searchable library, stored only on this Mac. Saving is your choice.")
            if !historyEnabled {
                RebuildSection(title: "YOUR LIBRARY IS OFF") {
                    Text(
                        "Recordings still become text and reach your clipboard. Enable history to keep future transcripts here."
                    )
                    Toggle("Save future transcripts", isOn: $historyEnabled)
                }
                Spacer()
            } else {
                HStack {
                    TextField("Search your transcripts", text: $search).textFieldStyle(.roundedBorder)
                    Button(exporting ? "Exporting…" : "Export…") { chooseExport() }
                        .disabled(loading || exporting)
                    Button("Clear library…", role: .destructive) { confirmClear = true }.disabled(loading || exporting)
                }
                if exporting {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Exported \(exportedCount) transcripts…").font(.caption)
                        Button("Cancel export") { exportTask?.cancel() }
                    }
                }
                if let exportStatus { Text(exportStatus).font(.caption).textSelection(.enabled) }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if records.isEmpty && !loading {
                    if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView(
                            "Room for your next idea", systemImage: "text.book.closed",
                            description: Text("Saved transcripts appear here after your next recording."))
                    } else {
                        ContentUnavailableView {
                            Label("No matching transcripts", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try another search, or clear it to see your saved transcripts.")
                        } actions: {
                            Button("Clear search") { search = "" }
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(records) { record in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text(record.date, format: .dateTime.month().day().hour().minute())
                                        Spacer()
                                        Text("\(record.wordCount) words · \(record.provider)")
                                    }.font(.caption).foregroundStyle(.secondary)
                                    Text(record.text).font(.system(size: 14)).textSelection(.enabled)
                                    if let original = record.originalText, original != record.text {
                                        DisclosureGroup("Original transcript") {
                                            Text(original).font(.system(size: 14)).textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                            Button("Copy original") { PasteManager.copyToClipboard(original) }
                                        }
                                    }
                                    HStack {
                                        Button("Copy") { PasteManager.copyToClipboard(record.text) }
                                            .accessibilityLabel(
                                                "Copy transcript from \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                        Spacer()
                                        Button("Delete", role: .destructive) {
                                            pendingDelete = record
                                            confirmDelete = true
                                        }
                                        .disabled(exporting)
                                        .accessibilityLabel(
                                            "Delete transcript from \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                    }.font(.caption)
                                }.padding(20).background(.background, in: RoundedRectangle(cornerRadius: 10))
                            }
                            if hasMore { Button("Load more") { Task { await load(reset: false) } }.disabled(loading) }
                        }
                    }
                }
                if loading { ProgressView().controlSize(.small) }
            }
        }.padding(36)
            .task(id: LoadRequest(
                search: search, enabled: historyEnabled, revision: history.historyRevision.value)
            ) {
                do {
                    try await Task.sleep(for: .milliseconds(200))
                    await load(reset: true)
                } catch {}
            }
            .confirmationDialog("Delete every saved transcript permanently?", isPresented: $confirmClear) {
                Button("Clear library", role: .destructive) {
                    Task {
                        do {
                            try await history.deleteAllRecords()
                            await load(reset: true)
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
            .confirmationDialog("Delete this transcript permanently?", isPresented: $confirmDelete) {
                Button("Delete transcript", role: .destructive) {
                    Task {
                        guard let record = pendingDelete else { return }
                        do {
                            try await history.deleteRecord(record)
                            await load(reset: true)
                        } catch { self.error = error.localizedDescription }
                        pendingDelete = nil
                    }
                }
            }
    }

    private func load(reset: Bool) async {
        guard historyEnabled else {
            records = []
            return
        }
        loading = true
        defer { loading = false }
        let query = search
        let revision = history.historyRevision.value
        do {
            let page = try await history.fetchRecords(
                limit: 50, offset: reset ? 0 : records.count, search: query)
            guard !Task.isCancelled, query == search, revision == history.historyRevision.value else { return }
            records = reset ? page : records + page
            hasMore = page.count == 50
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func chooseExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "AudioWhisper transcripts.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let container = history.sharedModelContainer else {
                error = "Your local library is unavailable. Try reopening the app."
                return
            }
            exporting = true
            exportedCount = 0
            exportStatus = nil
            error = nil
            exportTask = Task { @MainActor in
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    exporting = false
                    exportTask = nil
                }
                do {
                    let count = try await HistoryExporter.export(container: container, to: url) { count in
                        await MainActor.run { exportedCount = count }
                    }
                    exportStatus = "Exported \(count) transcripts."
                } catch is CancellationError {
                    exportStatus = "Export cancelled. Your existing file was kept."
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}
