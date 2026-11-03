import Foundation

/// Disk I/O is isolated from recording and the main thread. Retention is bounded
/// by age, count and bytes; an unreadable archive is kept for explicit recovery.
actor DiagnosticStore {
    static let maximumBytes = 2 * 1_024 * 1_024
    static let maximumSessions = 100
    static let maximumWindows = 100
    let file: URL?
    private var loaded = false
    private var archive = DiagnosticArchive()
    private(set) var storageFailed = false

    init(file: URL?) { self.file = file }

    func append(_ record: DiagnosticRecord) {
        load()
        archive.sessions.removeAll { $0.id == record.id }
        archive.sessions.append(record)
        prune()
        save()
    }

    func append(_ event: DiagnosticWindowEvent) {
        load()
        archive.windows.append(event)
        prune()
        save()
    }

    func snapshot() -> DiagnosticArchive {
        load()
        prune()
        return archive
    }

    func export() throws -> Data {
        let snapshot = snapshot()
        guard !storageFailed else { throw CocoaError(.fileReadCorruptFile) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(snapshot)
    }

    func clear() throws {
        if let file, FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        archive = DiagnosticArchive()
        loaded = true
        storageFailed = false
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        archive.sessions = Array(archive.sessions.filter { $0.finished >= cutoff }.suffix(Self.maximumSessions))
        archive.windows = Array(archive.windows.filter { $0.date >= cutoff }.suffix(Self.maximumWindows))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let file, FileManager.default.fileExists(atPath: file.path) else { return }
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count <= Self.maximumBytes else { throw CocoaError(.fileReadTooLarge) }
            let decoded = try JSONDecoder().decode(DiagnosticArchive.self, from: data)
            guard decoded.schema == 1 else { throw CocoaError(.fileReadCorruptFile) }
            archive = decoded
            prune()
        } catch { storageFailed = true }
    }

    private func save() {
        guard let file, !storageFailed else { return }
        do {
            var data = try JSONEncoder().encode(archive)
            while data.count > Self.maximumBytes, !archive.sessions.isEmpty || !archive.windows.isEmpty {
                if !archive.sessions.isEmpty { archive.sessions.removeFirst() } else { archive.windows.removeFirst() }
                data = try JSONEncoder().encode(archive)
            }
            let directory = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { storageFailed = true }
    }
}
