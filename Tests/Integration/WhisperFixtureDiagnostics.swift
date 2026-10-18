import CoreML
import CryptoKit
import WhisperKit

/// Only observes the public speech fixture; never installed in the production decoder.
final class WhisperFixtureDiagnostics: LogitsFiltering {
    private var remaining = 12

    func filterLogits(_ logits: MLMultiArray, withTokens tokens: [Int]) -> MLMultiArray {
        guard remaining > 0 else { return logits }
        remaining -= 1
        let top = (0..<logits.count).max { logits[$0].floatValue < logits[$1].floatValue } ?? 0
        print("REAL_WHISPER_LOGITS tokens=\(tokens) shape=\(logits.shape) strides=\(logits.strides) type=\(logits.dataType.rawValue) top=\(top) value=\(logits[top])")
        return logits
    }

    static func describeFeatures(_ engine: WhisperKit, audio: URL) async throws {
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audio.path)
        guard let padded = AudioProcessor.padOrTrimAudio(fromArray: samples),
              let mel = try await engine.featureExtractor.logMelSpectrogram(fromAudio: padded) as? MLMultiArray,
              let encoded = try await engine.audioEncoder.encodeFeatures(mel) as? MLMultiArray else { return }
        for (name, array) in [("padded", padded), ("mel", mel), ("encoded", encoded)] {
            if let output = ProcessInfo.processInfo.environment["WHISPER_EXPORT_BOUNDARIES"], name != "padded" {
                let bits = (0..<array.count).map { Float16(array[$0].floatValue).bitPattern.littleEndian }
                let data = bits.withUnsafeBytes { Data($0) }
                let compressed = try NSData(data: data).compressed(using: .lzfse)
                let folder = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try compressed.write(to: folder.appendingPathComponent("whisper_reference_\(name).lzfse"))
            }
            var sum = 0.0
            var squares = 0.0
            var minimum = Double.infinity
            var maximum = -Double.infinity
            for index in 0..<array.count {
                let value = array[index].doubleValue
                sum += value
                squares += value * value
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
            let probe = stride(from: 0, to: array.count, by: max(array.count / 16, 1)).prefix(16).map { array[$0].floatValue }
            print("REAL_WHISPER_FEATURE name=\(name) shape=\(array.shape) strides=\(array.strides) min=\(minimum) max=\(maximum) mean=\(sum / Double(array.count)) rms=\(sqrt(squares / Double(array.count))) probe=\(probe)")
        }
    }

    static func describe(_ engine: WhisperKit) throws {
        print("REAL_WHISPER_MODEL variant=\(engine.modelVariant) logits=\(engine.textDecoder.logitsSize ?? 0) embeds=\(engine.audioEncoder.embedSize ?? 0)")
        if let tokenizer = engine.tokenizer {
            print("REAL_WHISPER_TOKENIZER token902=\(tokenizer.decode(tokens: [902])) fixture=\(tokenizer.encode(text: "The quick brown fox jumps over the lazy dog."))")
        }
        guard let folder = engine.modelFolder else { return }
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            for file in ["coremldata.bin", "model.mlmodel", "model.mil", "metadata.json", "weights/weight.bin"] {
                let name = "\(component).mlmodelc/\(file)"
                let url = folder.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    print("REAL_WHISPER_ASSET name=\(name) present=false")
                    continue
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                print("REAL_WHISPER_ASSET name=\(name) bytes=\(data.count) sha256=\(digest)")
            }
        }
    }
}

/// A diagnostic A/B: preserve mel values while removing row padding before Core ML encoding.
final class CompactMelEncoderDiagnostic: AudioEncoding {
    private let base: any AudioEncoding
    var embedSize: Int? { base.embedSize }

    init(base: any AudioEncoding) { self.base = base }

    func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
        guard let source = features as? MLMultiArray else { return try await base.encodeFeatures(features) }
        let compact = try MLMultiArray(shape: source.shape, dataType: source.dataType)
        for index in 0..<source.count { compact[index] = source[index] }
        print("REAL_WHISPER_COMPACT source=\(source.strides) compact=\(compact.strides)")
        return try await base.encodeFeatures(compact)
    }
}
