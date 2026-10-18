import Foundation
import SwiftData

struct TranscriptionCleanupVersion: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let modeName: String
    let text: String
    let writing: DictationWriting
    let modelRepo: String
}

enum HistoryCleanupError: String, LocalizedError {
    case deleted = "This transcript was deleted. The original library has not been changed."
    case oversized = "Writing versions are limited to 20,000 characters each."
    case unavailable = "Your local library is unavailable. Reopen the app and try again."
    var errorDescription: String? { rawValue }
}

extension TranscriptionRecord {
    var cleanupVersions: [TranscriptionCleanupVersion] {
        guard let data = cleanupVersionsData else { return [] }
        return (try? JSONDecoder().decode([TranscriptionCleanupVersion].self, from: data)) ?? []
    }
}

extension DataManagerProtocol {
    func appendCleanupVersion(recordID: UUID, version: TranscriptionCleanupVersion) async throws {
        guard let container = sharedModelContainer else { throw HistoryCleanupError.unavailable }
        guard version.text.count <= 20_000 else { throw HistoryCleanupError.oversized }
        try Task.checkCancellation()
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<TranscriptionRecord>(predicate: #Predicate { $0.id == recordID })
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { throw HistoryCleanupError.deleted }
        let existing = try record.cleanupVersionsData.map {
            try JSONDecoder().decode([TranscriptionCleanupVersion].self, from: $0)
        } ?? []
        guard !existing.contains(where: { $0.id == version.id }) else { return }
        let versions = Array((existing + [version]).suffix(10))
        let data = try JSONEncoder().encode(versions)
        guard data.count <= 1_048_576 else { throw HistoryCleanupError.oversized }
        record.cleanupVersionsData = data
        try context.save()
        historyRevision.advance()
    }
}
