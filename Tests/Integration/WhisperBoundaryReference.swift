import CoreML
import WhisperKit

/// Intermediate tensors from the public speech fixture, used only to isolate
/// encoder and decoder inference. The end-to-end tests still require real audio.
enum WhisperBoundaryReference {
    static func tensor(_ name: String, shape: [Int]) throws -> MLMultiArray {
        guard let url = Bundle.module.url(forResource: "whisper_reference_" + name,
                                          withExtension: "lzfse", subdirectory: "Resources") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let compressed = try Data(contentsOf: url)
        let data = try (compressed as NSData).decompressed(using: .lzfse) as Data
        let count = shape.reduce(1, *)
        guard data.count == count * 2 else { throw CocoaError(.fileReadCorruptFile) }
        let tensor = try MLMultiArray(shape: shape.map { NSNumber(value: $0) }, dataType: .float16)
        data.withUnsafeBytes { bytes in
            for index in 0..<count {
                let bits = UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: UInt16.self))
                tensor[index] = NSNumber(value: Float(Float16(bitPattern: bits)))
            }
        }
        return tensor
    }

    static func compareSynchronousEncoder(_ model: MLModel, mel: MLMultiArray, reference: MLMultiArray) throws {
        let input = AudioEncoderInput(melspectrogram_features: mel)
        let output = try model.prediction(from: input)
        withExtendedLifetime(output) {
            if let encoded = output.featureValue(for: "encoder_output_embeds")?.multiArrayValue {
                compare(encoded, with: reference, name: "encoded-synchronous")
            }
        }
    }

    static func compare(_ actual: MLMultiArray, with reference: MLMultiArray, name: String) {
        guard actual.shape == reference.shape else {
            print("REAL_WHISPER_BOUNDARY name=\(name) shapeMismatch=\(actual.shape) expected=\(reference.shape)")
            return
        }
        var maximum = 0.0
        var squares = 0.0
        for index in 0..<actual.count {
            let difference = actual[index].doubleValue - reference[index].doubleValue
            maximum = max(maximum, abs(difference))
            squares += difference * difference
        }
        print("REAL_WHISPER_BOUNDARY name=\(name) maxError=\(maximum) rmsError=\(sqrt(squares / Double(actual.count)))")
    }
}

final class ReferenceBoundaryEncoder: AudioEncoding {
    private let base: any AudioEncoding
    private let mel: MLMultiArray?
    private let encoded: MLMultiArray?
    var embedSize: Int? { base.embedSize }

    init(base: any AudioEncoding, mel: MLMultiArray? = nil, encoded: MLMultiArray? = nil) {
        self.base = base
        self.mel = mel
        self.encoded = encoded
    }

    func encodeFeatures(_ features: any FeatureExtractorOutputType) async throws -> (any AudioEncoderOutputType)? {
        if let encoded { return encoded }
        if let mel { return try await base.encodeFeatures(mel) }
        return try await base.encodeFeatures(features)
    }
}
