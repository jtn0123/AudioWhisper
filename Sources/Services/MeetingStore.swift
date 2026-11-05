import AVFAudio
import Foundation

/// Atomic manifests reference only files within a UUID-owned directory. Audio
/// is retained on failure; transcript and source-audio retention are independent.
struct MeetingStore: Sendable {
    let root: URL
    init(root: URL = RebuildStorage.root.appendingPathComponent("Meetings", isDirectory: true)) { self.root = root }

    func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }

    func save(_ document: MeetingDocument) throws {
        guard document.schemaVersion == 1, document.chunks.count <= 1_000, document.segments.count <= 20_000 else {
            throw MeetingError.document
        }
        let data = try JSONEncoder().encode(document)
        guard data.count <= 8_388_608 else { throw MeetingError.document }
        try FileManager.default.createDirectory(at: folder(document.id), withIntermediateDirectories: true)
        try data.write(to: folder(document.id).appendingPathComponent("meeting.json"), options: .atomic)
    }

    func load(_ id: UUID) throws -> MeetingDocument {
        let url = folder(id).appendingPathComponent("meeting.json")
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 8_388_608 else {
            throw MeetingError.document
        }
        var document = try JSONDecoder().decode(MeetingDocument.self, from: Data(contentsOf: url))
        guard document.id == id, document.schemaVersion == 1, document.chunks.count <= 1_000,
              document.segments.count <= 20_000 else { throw MeetingError.document }
        for chunk in document.chunks {
            guard chunk.offset.isFinite, chunk.duration.isFinite, chunk.offset >= 0, chunk.duration >= 0,
                  chunk.offset + chunk.duration <= 1_805 else { throw MeetingError.bounds }
            _ = try audioURL(document.id, filename: chunk.filename)
        }
        if document.status == .recording || document.status == .processing {
            document.status = .interrupted
            document.note = "The previous session ended before completion. Recoverable audio was kept."
            try recoverChunks(&document)
        }
        return document
    }

    func list() throws -> MeetingInventory {
        guard FileManager.default.fileExists(atPath: root.path) else {
            return MeetingInventory(entries: [], unreadableCount: 0, hasMore: false)
        }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .sorted {
                ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
            }
        var entries: [MeetingListEntry] = []
        var unreadable = 0
        for folder in folders.prefix(100) {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            do { entries.append(MeetingListEntry(try load(id))) } catch { unreadable += 1 }
        }
        return MeetingInventory(entries: entries.sorted { $0.startedAt > $1.startedAt },
                                unreadableCount: unreadable, hasMore: folders.count > 100)
    }

    func audioURL(_ id: UUID, filename: String) throws -> URL {
        let folder = folder(id).standardizedFileURL.resolvingSymlinksInPath()
        guard filename == (filename as NSString).lastPathComponent, filename.hasSuffix(".caf"), !filename.contains("..") else {
            throw MeetingError.document
        }
        let url = folder.appendingPathComponent(filename).resolvingSymlinksInPath()
        guard url.path.hasPrefix(folder.path + "/") else { throw MeetingError.document }
        return url
    }

    func removeAudio(_ document: inout MeetingDocument) throws {
        for chunk in document.chunks {
            let url = try audioURL(document.id, filename: chunk.filename)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        document.audioRetained = false
        try save(document)
    }

    func delete(_ id: UUID) throws { try FileManager.default.removeItem(at: folder(id)) }

    private func recoverChunks(_ document: inout MeetingDocument) throws {
        let files = try FileManager.default.contentsOfDirectory(at: folder(document.id), includingPropertiesForKeys: nil)
        let known = Set(document.chunks.map(\.filename))
        for file in files where file.pathExtension == "caf" && !known.contains(file.lastPathComponent) {
            let parts = file.deletingPathExtension().lastPathComponent.split(separator: "_")
            guard parts.count == 3, let source = MeetingAudioSource(rawValue: String(parts[0])),
                  let milliseconds = Double(parts[1]), let id = UUID(uuidString: String(parts[2])),
                  let url = try? audioURL(document.id, filename: file.lastPathComponent),
                  let audio = try? AVAudioFile(forReading: url), audio.length > 0 else { continue }
            let duration = Double(audio.length) / audio.processingFormat.sampleRate
            guard milliseconds >= 0, milliseconds / 1000 + duration <= 1_805 else { continue }
            document.chunks.append(MeetingAudioChunk(id: id, source: source, filename: file.lastPathComponent,
                                                     offset: milliseconds / 1000, duration: duration))
        }
    }
}
