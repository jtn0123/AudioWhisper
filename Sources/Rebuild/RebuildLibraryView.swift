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
    @State private var loaded = false
    @State private var hasMore = false
    @State private var pendingDelete: TranscriptionRecord?
    @State private var confirmDelete = false
    @State private var confirmClear = false
    @State private var exporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var exportedCount = 0
    @State private var exportStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !historyEnabled {
                historyOff
            } else {
                toolbar
                if exporting { exportProgress }
                if let exportStatus {
                    RebuildCallout(tone: exportStatus.hasPrefix("Export cancelled") ? .info : .success, message: exportStatus)
                }
                if let error {
                    RebuildCallout(tone: .error, message: error) {
                        Button("Try again") { Task { await load(reset: true) } }.disabled(loading)
                    }
                }
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
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

    // MARK: Parts

    private var historyOff: some View {
        ContentUnavailableView {
            Label("Your library is off", systemImage: "text.book.closed")
        } description: {
            Text("Recordings still become text and reach your clipboard. Turn on saving to keep future transcripts here.")
        } actions: {
            Button("Save future transcripts") { historyEnabled = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Search transcripts", text: $search, prompt: Text("Search transcripts"))
                .textFieldStyle(.roundedBorder).frame(maxWidth: 340)
                .accessibilityLabel("Search transcripts")
            if loading && loaded { ProgressView().controlSize(.small) }
            Spacer(minLength: 8)
            if loaded && !records.isEmpty {
                Text(countText).font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText).lineLimit(1)
            }
            Button(exporting ? "Exporting…" : "Export…") { chooseExport() }
                .disabled(loading || exporting)
                .help("Save every transcript to a plain text file")
            Menu {
                Button("Clear library…", role: .destructive) { confirmClear = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .disabled(loading || exporting)
            .help("More library actions")
            .accessibilityLabel("More library actions")
        }
    }

    private var countText: String {
        let count = hasMore ? "\(records.count)+" : "\(records.count)"
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return records.count == 1 ? "1 match" : "\(count) matches" }
        return records.count == 1 ? "1 transcript" : "\(count) transcripts"
    }

    private var exportProgress: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Exported \(exportedCount) transcripts…").font(.system(size: 12)).monospacedDigit()
            Spacer()
            Button("Cancel export") { exportTask?.cancel() }
        }.rebuildCard(padding: 10)
    }

    @ViewBuilder private var content: some View {
        if !loaded && records.isEmpty && error == nil {
            ProgressView("Loading your library…").controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if records.isEmpty && !loading {
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
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(records) { record in
                        RebuildLibraryRow(record: record, deleteDisabled: exporting) {
                            pendingDelete = record
                            confirmDelete = true
                        }
                    }
                    if hasMore {
                        Button("Load more") { Task { await load(reset: false) } }.disabled(loading)
                            .frame(maxWidth: .infinity)
                    }
                }.padding(.bottom, 8)
            }
        }
    }

    /// Whether a saved transcript starts collapsed behind Show more. Previews
    /// that don't collapse are bounded by this length, so rows stay small.
    static func collapsesPreview(_ text: String) -> Bool {
        text.count > 360 || text.filter { $0 == "\n" }.count >= 5
    }

    // MARK: Loading and export

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
            loaded = true
        } catch {
            self.error = error.localizedDescription
            loaded = true
        }
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

/// One saved transcript: metadata, a bounded preview that can expand, and
/// the original words when writing cleanup changed them.
private struct RebuildLibraryRow: View {
    let record: TranscriptionRecord
    let deleteDisabled: Bool
    let onDelete: () -> Void
    @State private var expanded = false
    @State private var showOriginal = false

    private var dateText: String { record.date.formatted(date: .abbreviated, time: .shortened) }
    private var original: String? { record.originalText.flatMap { $0 == record.text ? nil : $0 } }
    private var isLong: Bool { RebuildLibraryView.collapsesPreview(record.text) }

    private var providerName: String {
        switch TranscriptionProvider(rawValue: record.provider) {
        case .local: return "Whisper"
        case .parakeet: return "Parakeet"
        case nil: return record.provider
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(record.date, format: .dateTime.month().day().hour().minute())
                Text("·")
                Text("\(record.wordCount) words")
                Text("·")
                Text(providerName)
                if original != nil {
                    Text("·")
                    Text("Cleaned up").fontWeight(.medium).foregroundStyle(RebuildTheme.accentText)
                }
            }
            .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            .accessibilityElement(children: .combine)
            Text(record.text).font(.system(size: 13.5)).lineSpacing(2).textSelection(.enabled)
                // Only cap rows that offer Show more; a short preview of wide
                // characters may wrap past five lines and must stay readable.
                .lineLimit(isLong && !expanded ? 5 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
            if showOriginal, let original { originalBlock(original) }
        }.rebuildCard(padding: 14)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button("Copy") { PasteManager.copyToClipboard(record.text) }
                .accessibilityLabel("Copy transcript from \(dateText)")
            if isLong {
                Button(expanded ? "Show less" : "Show more") { expanded.toggle() }.buttonStyle(.rebuildLink)
            }
            if original != nil {
                Button(showOriginal ? "Hide original" : "Original transcript") { showOriginal.toggle() }
                    .buttonStyle(.rebuildLink)
                    .accessibilityLabel(showOriginal ? "Hide original transcript" : "Show original transcript")
            }
            Spacer()
            Button("Delete", role: .destructive, action: onDelete)
                .disabled(deleteDisabled)
                .accessibilityLabel("Delete transcript from \(dateText)")
        }
        .font(.system(size: 12))
        .controlSize(.small)
    }

    private func originalBlock(_ original: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Original transcript").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(RebuildTheme.secondaryText)
            Text(original).font(.system(size: 13.5)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Copy original") { PasteManager.copyToClipboard(original) }.controlSize(.small)
        }
        .padding(10)
        .background(RebuildTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
