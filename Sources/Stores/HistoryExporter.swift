import Foundation
import SwiftData

enum HistoryExporter {
    /// Construct the model actor off the UI executor; cancellation follows the
    /// detached worker through the last write and before replacing any file.
    static func export(
        container: ModelContainer, to destination: URL,
        progress: @escaping @Sendable (Int) async -> Void = { _ in }
    ) async throws -> Int {
        let worker = Task.detached(priority: .utility) {
            let exporter = HistoryExportWorker(modelContainer: container)
            return try await exporter.write(to: destination, progress: progress)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }
}

@ModelActor
private actor HistoryExportWorker {
    func write(to destination: URL, progress: @Sendable (Int) async -> Void) async throws -> Int {
        try Task.checkCancellation()
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID()).txt")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data().write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        let started = Date()
        var count = 0
        while true {
            try Task.checkCancellation()
            // Normal recordings saved after export starts belong to the next export.
            var descriptor = FetchDescriptor<TranscriptionRecord>(
                predicate: #Predicate { $0.date <= started },
                sortBy: [SortDescriptor(\.date, order: .reverse)])
            descriptor.fetchLimit = 500
            descriptor.fetchOffset = count
            let page = try modelContext.fetch(descriptor)
            if page.isEmpty { break }
            for record in page {
                try Task.checkCancellation()
                let separator = count == 0 ? "" : "\n\n---\n\n"
                let text = "\(separator)\(record.date.formatted())\n\(record.text)"
                try handle.write(contentsOf: Data(text.utf8))
                count += 1
            }
            await progress(count)
            if page.count < 500 { break }
        }
        try Task.checkCancellation()
        try handle.synchronize()
        try handle.close()
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
        return count
    }
}
