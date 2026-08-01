// MARK: - Transcription Pipeline Configuration

/// Configuration for the transcription pipeline.
internal struct TranscriptionPipelineConfig {
    let provider: TranscriptionProvider
    let whisperModel: WhisperModel?
    let applySemanticCorrection: Bool
    let sourceAppBundleId: String?

    init(
        provider: TranscriptionProvider,
        whisperModel: WhisperModel? = nil,
        applySemanticCorrection: Bool = true,
        sourceAppBundleId: String? = nil
    ) {
        self.provider = provider
        self.whisperModel = whisperModel
        self.applySemanticCorrection = applySemanticCorrection
        self.sourceAppBundleId = sourceAppBundleId
    }
}

// MARK: - Audio MIME Types
