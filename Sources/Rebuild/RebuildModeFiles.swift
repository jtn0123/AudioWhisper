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
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                guard size <= 1_048_576 else { throw DictationModeArchive.ArchiveError.oversized }
                completion(.success(try Data(contentsOf: url)))
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
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try DictationModeArchive.export(modes).write(to: url, options: .atomic)
                completion(nil)
            } catch { completion(error.localizedDescription) }
        }
    }
}
