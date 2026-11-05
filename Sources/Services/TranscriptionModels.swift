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
    /// Vocabulary and rule-based formatting; identity unless a session opts in.
    let formatting: TranscriptFormattingOptions
    let language: DictationLanguage
    let writing: DictationWriting
    let context: CapturedWritingContext?

    init(
        provider: TranscriptionProvider,
        whisperModel: WhisperModel? = nil,
        applySemanticCorrection: Bool = true,
        sourceAppBundleId: String? = nil,
        parakeetModel: ParakeetModel? = nil,
        correctionMode: SemanticCorrectionMode? = nil,
        correctionModelRepo: String? = nil,
        formatting: TranscriptFormattingOptions = .none,
        language: DictationLanguage = .automatic,
        writing: DictationWriting = DictationWriting(),
        context: CapturedWritingContext? = nil
    ) {
        self.provider = provider
        self.whisperModel = whisperModel
        self.applySemanticCorrection = applySemanticCorrection
        self.sourceAppBundleId = sourceAppBundleId
        self.parakeetModel = parakeetModel
        self.correctionMode = correctionMode
        self.correctionModelRepo = correctionModelRepo
        self.formatting = formatting
        self.language = language
        self.writing = writing
        self.context = context
    }
}

// MARK: - Audio MIME Types
