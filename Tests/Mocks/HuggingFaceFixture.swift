import Foundation

/// Structurally complete tiny assets for cache-policy tests, never inference.
enum HuggingFaceFixture {
    static func writeAssets(to snapshot: URL) throws {
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("config.json"))
        try Data("{}".utf8).write(to: snapshot.appendingPathComponent("tokenizer.json"))
        let header = Data(#"{"w":{"dtype":"U8","shape":[1],"data_offsets":[0,1]}}"#.utf8)
        var length = UInt64(header.count).littleEndian
        var weights = withUnsafeBytes(of: &length) { Data($0) }
        weights.append(header)
        weights.append(1)
        try weights.write(to: snapshot.appendingPathComponent("model.safetensors"))
    }
}
