import CoreML
import CryptoKit
import WhisperKit

/// Diagnostic only. The embedded specification and compiled artifact report
/// different conversion provenance, so this is not an identical-graph control.
enum EmbeddedEncoderExperiment {
    static func run(modelPath: String, audio: URL) async throws -> [String] {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try makePackage(from: URL(fileURLWithPath: modelPath).appendingPathComponent("AudioEncoder.mlmodelc"), at: root)
        let compiled = try await MLModel.compileModel(at: package)
        defer { try? FileManager.default.removeItem(at: compiled) }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        let model = try MLModel(contentsOf: compiled, configuration: configuration)
        let engine = try await WhisperKit(WhisperKitConfig(modelFolder: modelPath,
            computeOptions: ModelComputeOptions(melCompute: .cpuOnly, audioEncoderCompute: .cpuOnly, textDecoderCompute: .cpuOnly),
            download: false))
        guard let encoder = engine.audioEncoder as? AudioEncoder else { throw CocoaError(.coderInvalidValue) }
        encoder.model = model
        let mel = try WhisperBoundaryReference.tensor("mel", shape: [1, 80, 1, 3000])
        let reference = try WhisperBoundaryReference.tensor("encoded", shape: [1, 512, 1, 1500])
        guard let actual = try await encoder.encodeFeatures(mel) as? MLMultiArray else { throw CocoaError(.coderInvalidValue) }
        WhisperBoundaryReference.compare(actual, with: reference, name: "embedded-recompiled-encoded")
        var texts: [String] = []
        for run in 0..<2 {
            let results = try await engine.transcribe(audioPath: audio.path)
            let text = results.map { $0.text }.joined(separator: " ")
            print("REAL_WHISPER_EMBEDDED_RECOMPILE run=\(run) text=\(text)")
            texts.append(text)
        }
        return texts
    }

    private static func makePackage(from original: URL, at root: URL) throws -> URL {
        let package = root.appendingPathComponent("AudioEncoder.mlpackage", isDirectory: true)
        let dataRoot = package.appendingPathComponent("Data/com.apple.CoreML", isDirectory: true)
        try FileManager.default.createDirectory(at: dataRoot, withIntermediateDirectories: true)
        let source = original.appendingPathComponent("model.mlmodel")
        let weights = original.appendingPathComponent("weights")
        try FileManager.default.copyItem(at: source, to: dataRoot.appendingPathComponent("model.mlmodel"))
        try FileManager.default.copyItem(at: weights, to: dataRoot.appendingPathComponent("weights"))
        let modelID = UUID().uuidString
        let weightsID = UUID().uuidString
        let manifest: [String: Any] = ["fileFormatVersion": "1.0.0", "rootModelIdentifier": modelID,
            "itemInfoEntries": [
                modelID: ["author": "com.apple.CoreML", "description": "CoreML Model Specification",
                          "name": "model.mlmodel", "path": "com.apple.CoreML/model.mlmodel"],
                weightsID: ["author": "com.apple.CoreML", "description": "CoreML Model Weights",
                            "name": "weights", "path": "com.apple.CoreML/weights"]]]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: package.appendingPathComponent("Manifest.json"), options: .atomic)
        let fingerprint = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        print("REAL_WHISPER_EMBEDDED_RECOMPILE sourceSHA256=\(fingerprint) alternateConversionProvenance=true")
        return package
    }
}
