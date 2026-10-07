import Foundation

enum HuggingFaceCache {
    static var root: URL {
        let env = ProcessInfo.processInfo.environment
        if let path = env["HF_HUB_CACHE"] ?? env["HUGGINGFACE_HUB_CACHE"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        if let path = env["HF_HOME"], !path.isEmpty { return URL(fileURLWithPath: path).appendingPathComponent("hub") }
        let base = env["XDG_CACHE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        return base.appendingPathComponent("huggingface/hub")
    }

    static func modelDirectory(repo: String, root: URL = root) -> URL {
        root.appendingPathComponent("models--" + repo.replacingOccurrences(of: "/", with: "--"))
    }

    static func completeSnapshot(in directory: URL) -> Bool {
        let fm = FileManager.default
        let ref = directory.appendingPathComponent("refs/main")
        guard let bytes = try? Data(contentsOf: ref), bytes.count <= 1024,
              let revision = String(data: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !revision.isEmpty, revision.allSatisfy(\.isHexDigit) else { return false }
        let snapshot = directory.appendingPathComponent("snapshots").appendingPathComponent(revision)
        let config = snapshot.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: config),
              (try? JSONSerialization.jsonObject(with: configData)) is [String: Any] else { return false }
        let hasTokenizer = ["tokenizer.json", "tokenizer.model"].contains {
            nonemptyFile(snapshot.appendingPathComponent($0))
        }
        guard hasTokenizer else { return false }
        let index = snapshot.appendingPathComponent("model.safetensors.index.json")
        if fm.fileExists(atPath: index.path) {
            guard let data = try? Data(contentsOf: index),
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let weights = json["weight_map"] as? [String: String], !weights.isEmpty else { return false }
            return Set(weights.values).allSatisfy { name in
                !name.contains("/") && name.hasSuffix(".safetensors") && completeWeights(snapshot.appendingPathComponent(name))
            }
        }
        let files = (try? fm.contentsOfDirectory(at: snapshot, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.pathExtension == "safetensors" && completeWeights($0) }
    }

    private static func completeWeights(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard let size = try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 8, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let prefix = try? handle.read(upToCount: 8), prefix.count == 8 else { return false }
        let headerSize = prefix.enumerated().reduce(UInt64(0)) { $0 | (UInt64($1.element) << ($1.offset * 8)) }
        guard headerSize > 0, headerSize <= 16 * 1024 * 1024, headerSize < UInt64(size),
              let header = try? handle.read(upToCount: Int(headerSize)), header.count == Int(headerSize),
              let tensors = (try? JSONSerialization.jsonObject(with: header)) as? [String: Any] else { return false }
        let ends = tensors.filter { $0.key != "__metadata__" }.compactMap { entry -> Int? in
            ((entry.value as? [String: Any])?["data_offsets"] as? [Int])?.last
        }
        guard let end = ends.max(), end > 0 else { return false }
        return UInt64(end) <= UInt64(size) - headerSize - 8
    }

    private static func nonemptyFile(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath()
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && (values.fileSize ?? 0) > 0
    }
}
