import AppKit
import UniformTypeIdentifiers

@MainActor
enum RebuildModeFiles {
    enum ModeFileError: String, LocalizedError {
        case busy = "Finish the current job before changing modes."
        var errorDescription: String? { rawValue }
    }

    static func importModes(completion: @escaping (Result<Data, Error>) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                completion(.success(try read(url)))
            } catch { completion(.failure(error)) }
        }
    }

    static func export(_ modes: [SavedDictationMode], completion: @escaping (String?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AudioWhisper modes.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try write(modes, to: url)
                completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }

    static func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else { throw DictationModeArchive.ArchiveError.invalid }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        let maximum = DictationModeArchive.maximumBytes
        while data.count <= maximum {
            let chunk = try handle.read(upToCount: min(65_536, maximum + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= maximum else { throw DictationModeArchive.ArchiveError.oversized }
        return data
    }

    static func write(_ modes: [SavedDictationMode], to url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try DictationModeArchive.export(modes).write(to: url, options: .atomic)
    }

}
