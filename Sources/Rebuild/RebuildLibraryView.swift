import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RebuildLibraryView: View {
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
                    Button(exporting ? "Exporting…" : "Export…") { Task { await exportLibrary() } }
                        .disabled(loading || exporting)
                    Button("Clear library…", role: .destructive) { confirmClear = true }.disabled(loading || exporting)
                }
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                if records.isEmpty && !loading {
                    ContentUnavailableView(
                        "Room for your next idea", systemImage: "text.book.closed",
                        description: Text("Saved transcripts appear here after your next recording."))
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
                                    HStack {
                                        Button("Copy") { PasteManager.copyToClipboard(record.text) }
                                            .accessibilityLabel(
                                                "Copy transcript from \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                        Spacer()
                                        Button("Delete", role: .destructive) {
                                            pendingDelete = record
                                            confirmDelete = true
                                        }
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
                search: search, enabled: historyEnabled, revision: DataManager.shared.historyRevision.value)
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
                            try await DataManager.shared.deleteAllRecords()
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
                            try await DataManager.shared.deleteRecord(record)
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
        let revision = DataManager.shared.historyRevision.value
        do {
            let page = try await DataManager.shared.fetchRecords(
                limit: 50, offset: reset ? 0 : records.count, search: query)
            guard !Task.isCancelled, query == search, revision == DataManager.shared.historyRevision.value else { return }
            records = reset ? page : records + page
            hasMore = page.count == 50
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func exportLibrary() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.plainText]
        panel.nameFieldStringValue = "AudioWhisper transcripts.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        defer { exporting = false }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try Data().write(to: temporary)
            let handle = try FileHandle(forWritingTo: temporary)
            defer { try? handle.close() }
            var writeError: Error?
            var first = true
            try await DataManager.shared.forEachRecordPage(pageSize: 500) { page in
                guard writeError == nil else { return }
                let text = page.map { record in
                    let separator = first ? "" : "\n\n---\n\n"
                    first = false
                    return "\(separator)\(record.date.formatted())\n\(record.text)"
                }.joined()
                do { try handle.write(contentsOf: Data(text.utf8)) } catch { writeError = error }
            }
            if let writeError { throw writeError }
            try handle.synchronize()
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
