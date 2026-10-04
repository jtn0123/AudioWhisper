// MARK: - Transcription Pipeline Configuration

/// Configuration for the transcription pipeline.
internal struct TranscriptionPipelineConfig: Sendable {
    let provider: TranscriptionProvider
    let whisperModel: WhisperModel?
    let applySemanticCorrection: Bool
    let sourceAppBundleId: String?
    let parakeetModel: ParakeetModel?
    let correctionMode: SemanticCorrectionMode?
    let correctionModelRepo: String?

    init(
        provider: TranscriptionProvider,
        whisperModel: WhisperModel? = nil,
        applySemanticCorrection: Bool = true,
        sourceAppBundleId: String? = nil,
        parakeetModel: ParakeetModel? = nil,
        correctionMode: SemanticCorrectionMode? = nil,
        correctionModelRepo: String? = nil
    ) {
        self.provider = provider
        self.whisperModel = whisperModel
        self.applySemanticCorrection = applySemanticCorrection
        self.sourceAppBundleId = sourceAppBundleId
        self.parakeetModel = parakeetModel
        self.correctionMode = correctionMode
        self.correctionModelRepo = correctionModelRepo
    }
}

// MARK: - Audio MIME Types
