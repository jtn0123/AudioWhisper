import CryptoKit
import Foundation

@MainActor
struct RebuildModelVerificationStore {
    private struct Failure: Codable {
        let assets: String?
        let message: String
    }
    private let defaults: UserDefaults
    private let key = "rebuild.failedModelVerifications"

    init(defaults: UserDefaults) { self.defaults = defaults }

    func failure(for selection: RebuildModelSelection, assets: String?) -> String? {
        guard let failure = failures[selection.key], failure.assets == assets else { return nil }
        return failure.message
    }

    func record(_ result: ModelVerificationResult, for selection: RebuildModelSelection, assets: String?) {
        var current = failures
        if result.succeeded { current.removeValue(forKey: selection.key) } else {
            current[selection.key] = Failure(assets: assets, message: result.message)
        }
        if let data = try? JSONEncoder().encode(current) { defaults.set(data, forKey: key) }
    }

    private var failures: [String: Failure] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Failure].self, from: data)) ?? [:]
    }
}

/// Metadata identity invalidates an old load verdict when its assets change.
/// It is deliberately distinct from cryptographic model integrity validation.
enum RebuildModelAssetIdentity {
    static func root(for selection: RebuildModelSelection) -> URL? {
        if selection.provider == .local { return WhisperKitStorage.modelDirectory(for: selection.whisper) }
        guard let revision = ModelPins.revision(for: selection.parakeet.rawValue) else { return nil }
        return HuggingFaceCache.modelDirectory(repo: selection.parakeet.rawValue)
            .appendingPathComponent("snapshots").appendingPathComponent(revision)
    }

    static func fingerprint(at root: URL) -> String? {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let files = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return nil }
        var entries: [String] = []
        for case let file as URL in files {
            guard let values = try? file.resolvingSymlinksInPath().resourceValues(forKeys: keys) else { return nil }
            guard values.isRegularFile == true else { continue }
            entries.append("\(file.path)|\(values.fileSize ?? 0)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        guard !entries.isEmpty else { return nil }
        let data = Data(entries.sorted().joined(separator: "\n").utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
