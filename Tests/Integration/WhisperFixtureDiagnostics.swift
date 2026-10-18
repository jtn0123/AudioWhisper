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

    static func describe(_ engine: WhisperKit) throws {
        print("REAL_WHISPER_MODEL variant=\(engine.modelVariant) logits=\(engine.textDecoder.logitsSize ?? 0) embeds=\(engine.audioEncoder.embedSize ?? 0)")
        if let tokenizer = engine.tokenizer {
            print("REAL_WHISPER_TOKENIZER token902=\(tokenizer.decode(tokens: [902])) fixture=\(tokenizer.encode(text: "The quick brown fox jumps over the lazy dog."))")
        }
        guard let folder = engine.modelFolder else { return }
        for component in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            for file in ["model.mil", "weights/weight.bin"] {
                let name = "\(component).mlmodelc/\(file)"
                let data = try Data(contentsOf: folder.appendingPathComponent(name), options: .mappedIfSafe)
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                print("REAL_WHISPER_ASSET name=\(name) bytes=\(data.count) sha256=\(digest)")
            }
        }
    }
}
