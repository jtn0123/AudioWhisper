import CoreML
@preconcurrency import WhisperKit

enum WhisperEngineFactory {
    static func make(model: WhisperModel, folder: String) async throws -> WhisperKit {
        let engine = try await WhisperKit(WhisperKitConfig(
            downloadBase: RebuildStorage.whisperDownloadBase, modelFolder: folder, download: false))
        let compute = engine.modelCompute.audioEncoderCompute
        if let prepared = try await PreparedWhisperEncoder().prepare(
            model: model, folder: URL(fileURLWithPath: folder), compute: compute) {
            guard let encoder = engine.audioEncoder as? AudioEncoder else {
                throw PreparedWhisperEncoder.PreparationError.shape
            }
            let configuration = MLModelConfiguration()
            configuration.computeUnits = compute
            encoder.model = try MLModel(contentsOf: prepared, configuration: configuration)
        }
        return engine
    }
}
