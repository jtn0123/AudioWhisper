import SwiftUI
import SwiftData
import AppKit

@MainActor
internal struct TranscriptionHistoryView: View {
    // Data loading + pagination is owned by the view model (audit item A2);
    // the view no longer touches `DataManager` directly.
    @State private var viewModel: TranscriptionHistoryViewModel

    // Purely-UI state stays in the view.
    @State private var searchText = ""
    @State private var recordToDelete: TranscriptionRecord?
    @State private var showDeleteConfirmation = false
    @State private var expandedRecords: Set<TranscriptionRecord.ID> = []
    @FocusState private var isSearchFocused: Bool

    init(viewModel: TranscriptionHistoryViewModel? = nil) {
        self._viewModel = State(initialValue: viewModel ?? TranscriptionHistoryViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            TranscriptionHistoryHeader(
                title: "Transcription History",
                subtitle: subtitleText,
                showClearAll: !viewModel.records.isEmpty,
                onClearAll: showClearAllConfirmation
            )

            Divider()

            TranscriptionSearchBar(
                searchText: $searchText,
                isFocused: $isSearchFocused
            )

            if viewModel.isLoading && viewModel.records.isEmpty {
                TranscriptionHistoryLoadingView()
            } else if viewModel.records.isEmpty && viewModel.hasLoadedOnce {
                TranscriptionHistoryEmptyState(
                    searchText: searchText,
                    onClearSearch: {
                        searchText = ""
                        isSearchFocused = false
                    }
                )
            } else {
                TranscriptionRecordsList(
                    records: viewModel.records,
                    expandedRecords: expandedRecords,
                    onToggleExpand: toggleExpansion(for:),
                    onCopy: { copyToClipboard($0.text) },
                    onDelete: confirmDelete,
                    onLastRowAppear: {
                        if viewModel.hasMore && !viewModel.isLoading {
                            Task { await viewModel.loadRecords(search: searchText) }
                        }
                    }
                )
            }
        }
        .task {
            await viewModel.loadRecords(reset: true, search: searchText)
        }
        .onChange(of: searchText) { _, newValue in
            Task { await viewModel.loadRecords(reset: true, search: newValue) }
        }
        .alert("Delete Record", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let record = recordToDelete {
                    Task { await viewModel.deleteRecord(record, search: searchText) }
                }
            }
        } message: {
            Text("Are you sure you want to delete this transcription record? This action cannot be undone.")
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .frame(
            minWidth: LayoutMetrics.TranscriptionHistory.minimumSize.width,
            minHeight: LayoutMetrics.TranscriptionHistory.minimumSize.height
        )
        .onKeyPress(.escape) {
            handleEscapeKey()
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "f")) { keyPress in
            if keyPress.modifiers.contains(.command) {
                return handleCommandF()
            }
            return .ignored
        }
    }

    private func copyToClipboard(_ text: String) {
        PasteManager.copyToClipboard(text)
    }

    private func confirmDelete(_ record: TranscriptionRecord) {
        recordToDelete = record
        showDeleteConfirmation = true
    }

    private func showClearAllConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Clear All Transcription History"
        alert.informativeText = "Are you sure you want to delete all transcription records? This action cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Clear All")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            Task { await viewModel.clearAllRecords(search: searchText) }
        }
    }

    private func toggleExpansion(for record: TranscriptionRecord) {
        if expandedRecords.contains(record.id) {
            expandedRecords.remove(record.id)
        } else {
            expandedRecords.insert(record.id)
        }
    }

    private var subtitleText: String {
        let loadedCount = viewModel.records.count

        if loadedCount == 0 {
            return "No records"
        }

        let noun = loadedCount == 1 ? "record" : "records"
        let suffix = viewModel.hasMore ? "+" : ""

        if searchText.isEmpty {
            return "\(loadedCount)\(suffix) \(noun)"
        } else {
            return "\(loadedCount)\(suffix) matching \(noun)"
        }
    }

}

// MARK: - View Extensions

internal extension TranscriptionHistoryView {

    private func handleEscapeKey() -> KeyPress.Result {
        if isSearchFocused {
            searchText = ""
            isSearchFocused = false
            return .handled
        }
        return .ignored
    }

    private func handleCommandF() -> KeyPress.Result {
        isSearchFocused = true
        return .handled
    }
}

// MARK: - Preview

#Preview("With Records") {
    let previewContainer: ModelContainer = {
        do {
            let container = try ModelContainer(
                for: TranscriptionRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)

            // Add sample data
            let sampleRecords = [
                TranscriptionRecord(
                    text: "This is a sample transcription from the Parakeet speech engine. "
                        + "It demonstrates how the history view will look with longer text content.",
                    provider: .parakeet,
                    duration: 12.5
                ),
                TranscriptionRecord(text: "Short test", provider: .local, duration: 2.1, modelUsed: "base"),
                TranscriptionRecord(
                    text: "Another example transcription that shows how multiple records "
                        + "are displayed in the history view.",
                    provider: .parakeet,
                    duration: 8.3
                )
            ]

            for record in sampleRecords {
                context.insert(record)
            }

            try context.save()
            return container
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }()

    TranscriptionHistoryView()
        .modelContainer(previewContainer)
        .frame(
            width: LayoutMetrics.TranscriptionHistory.previewSize.width,
            height: LayoutMetrics.TranscriptionHistory.previewSize.height
        )
}

#Preview("Empty State") {
    let previewContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: TranscriptionRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }()

    TranscriptionHistoryView()
        .modelContainer(previewContainer)
        .frame(
            width: LayoutMetrics.TranscriptionHistory.previewSize.width,
            height: LayoutMetrics.TranscriptionHistory.previewSize.height
        )
}
