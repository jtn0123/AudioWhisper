import Foundation

/// Only processing preferences belong to a mode. Consent, delivery, microphone,
/// history retention and shortcuts remain independent user choices.
struct DictationModeSettings: Codable, Equatable, Sendable {
    var provider: TranscriptionProvider
    var whisper: WhisperModel
    var parakeet: ParakeetModel
    var cleanup: SemanticCorrectionMode
    var cleanupModel: String
    var vocabulary: String
    var removeFillers: Bool
    var spokenPunctuation: Bool
    var language: DictationLanguage = .automatic
    var writing = DictationWriting()

    enum CodingKeys: String, CodingKey {
        case provider, whisper, parakeet, cleanup, cleanupModel, vocabulary, removeFillers, spokenPunctuation, language, writing
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decode(TranscriptionProvider.self, forKey: .provider)
        whisper = try values.decode(WhisperModel.self, forKey: .whisper)
        parakeet = try values.decode(ParakeetModel.self, forKey: .parakeet)
        cleanup = try values.decode(SemanticCorrectionMode.self, forKey: .cleanup)
        cleanupModel = try values.decode(String.self, forKey: .cleanupModel)
        vocabulary = try values.decode(String.self, forKey: .vocabulary)
        removeFillers = try values.decode(Bool.self, forKey: .removeFillers)
        spokenPunctuation = try values.decode(Bool.self, forKey: .spokenPunctuation)
        language = try values.decodeIfPresent(DictationLanguage.self, forKey: .language) ?? .automatic
        writing = try values.decodeIfPresent(DictationWriting.self, forKey: .writing) ?? DictationWriting()
    }

    init(provider: TranscriptionProvider, whisper: WhisperModel, parakeet: ParakeetModel,
         cleanup: SemanticCorrectionMode, cleanupModel: String, vocabulary: String,
         removeFillers: Bool, spokenPunctuation: Bool, language: DictationLanguage = .automatic,
         writing: DictationWriting = DictationWriting()) {
        self.provider = provider
        self.whisper = whisper
        self.parakeet = parakeet
        self.cleanup = cleanup
        self.cleanupModel = cleanupModel
        self.vocabulary = vocabulary
        self.removeFillers = removeFillers
        self.spokenPunctuation = spokenPunctuation
        self.language = language
        self.writing = writing
    }

    var formatting: TranscriptFormattingOptions {
        TranscriptFormattingOptions(vocabulary: CustomVocabulary(parsing: vocabulary),
                                    removeFillers: removeFillers, spokenPunctuation: spokenPunctuation)
    }

    func pipeline(sourceApp: String? = nil, context: CapturedWritingContext? = nil) -> TranscriptionPipelineConfig {
        TranscriptionPipelineConfig(provider: provider, whisperModel: whisper, applySemanticCorrection: cleanup != .off,
            sourceAppBundleId: sourceApp, parakeetModel: parakeet, correctionMode: cleanup,
            correctionModelRepo: cleanupModel, formatting: formatting, language: language, writing: writing, context: context)
    }
}

struct SavedDictationMode: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let settings: DictationModeSettings

    enum ValidationError: String, LocalizedError {
        case name = "Use a mode name between 1 and 60 characters."
        case duplicate = "A mode with that name already exists. Choose another name."
        case limit = "You can save up to 32 modes. Remove one before adding another."
        var errorDescription: String? { rawValue }
    }

    static func make(name: String, settings: DictationModeSettings, existing: [Self]) throws -> Self {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 60, !trimmed.contains(where: \.isNewline) else {
            throw ValidationError.name
        }
        guard !existing.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            throw ValidationError.duplicate
        }
        guard existing.count < 32 else { throw ValidationError.limit }
        return Self(id: UUID(), name: trimmed, settings: settings)
    }
}

extension AppDefaults {
    static var selectedDictationModeID: UUID? {
        get { defaults.string(forKey: Key.selectedDictationModeID.rawValue).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.selectedDictationModeID.rawValue) }
    }

    static var activeDictationModeID: UUID? {
        savedDictationModes.first { $0.id == selectedDictationModeID && $0.settings == currentDictationSettings }?.id
    }

    static var savedDictationModes: [SavedDictationMode] {
        get {
            guard let data = defaults.data(forKey: Key.savedDictationModes.rawValue) else { return [] }
            return (try? JSONDecoder().decode([SavedDictationMode].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: Key.savedDictationModes.rawValue)
        }
    }

    /// Applying a saved setup changes subsequent sessions. RebuildSession already
    /// snapshots these preferences before capture, so active jobs and retries keep theirs.
    static var currentDictationSettings: DictationModeSettings {
        get {
            DictationModeSettings(
                provider: transcriptionProvider, whisper: selectedWhisperModel, parakeet: selectedParakeetModel,
                cleanup: semanticCorrectionMode, cleanupModel: semanticCorrectionModelRepo,
                vocabulary: customVocabulary, removeFillers: removeFillerWords, spokenPunctuation: spokenPunctuation,
                language: dictationLanguage, writing: dictationWriting)
        }
        set {
            selectedDictationModeID = nil
            transcriptionProvider = newValue.provider
            selectedWhisperModel = newValue.whisper
            selectedParakeetModel = newValue.parakeet
            semanticCorrectionMode = newValue.cleanup
            semanticCorrectionModelRepo = newValue.cleanupModel
            customVocabulary = newValue.vocabulary
            removeFillerWords = newValue.removeFillers
            spokenPunctuation = newValue.spokenPunctuation
            dictationLanguage = newValue.language
            dictationWriting = newValue.writing
        }
    }
}
