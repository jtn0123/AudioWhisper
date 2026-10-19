import Foundation
@preconcurrency import WhisperKit

// Actor to manage WhisperKit instances safely across concurrency boundaries.
// Audit item B3: keys are the typed `WhisperModel` enum, not the raw model
// name string. The enum's `rawValue` is reserved for interfacing with
// WhisperKit's external API (e.g. `WhisperKitConfig(model:)`).
private actor WhisperKitCache {
    private var instances: [WhisperModel: WhisperKit] = [:]
    /// Access-time bookkeeping and eviction policy (audit item D2).
    private var lru = LRUAccessTracker<WhisperModel>()

    func getOrCreate(
        model: WhisperModel,
        maxCached: Int,
        progressCallback: (@Sendable (String) -> Void)?
    ) async throws -> WhisperKit {
        // Check if we have a cached instance
        if let existingInstance = instances[model] {
            // Update access time for LRU tracking
            lru.touch(model)
            return existingInstance
        }

        // Check if model is downloaded locally before attempting to create WhisperKit instance
        if !(await isModelDownloadedLocally(model)) {
            throw LocalWhisperError.modelNotDownloaded
        }

        evictLeastRecentlyUsedIfNeeded(maxCached: maxCached)

        // Create new instance
        progressCallback?("Preparing \(model.displayName) model...")

        // Set environment variables to ensure offline operation
        setenv("HF_HUB_OFFLINE", "1", 1)
        setenv("TRANSFORMERS_OFFLINE", "1", 1)
        setenv("HF_HUB_DISABLE_IMPLICIT_TOKEN", "1", 1)

        // Try to use local model path if available
        let newInstance: WhisperKit
        do {
            guard let localModelPath = getLocalModelPath(for: model) else {
                throw LocalWhisperError.modelNotDownloaded
            }
            newInstance = try await WhisperEngineFactory.make(model: model, folder: localModelPath)
        } catch {
            // Decide whether this is a "model not downloaded" situation without
            // relying on locale-/version-fragile English substrings.
            //
            // 1. If the model files are no longer present on disk (e.g. a
            //    partial/cleared cache), it is definitively not downloaded.
            // 2. If WhisperKit attempted a network fetch and failed
            //    (URLError / NSURLErrorDomain), that also means the model
            //    wasn't available locally.
            if !(await isModelDownloadedLocally(model)) || LocalWhisperService.isNetworkError(error) {
                throw LocalWhisperError.modelNotDownloaded
            }
            throw error
        }

        // Cache the new instance
        instances[model] = newInstance
        lru.touch(model)

        return newInstance
    }

    func clear() {
        instances.removeAll()
        lru.removeAll()
    }

    func clearExceptMostRecent() {
        for key in lru.keysToEvictKeepingMostRecent() {
            instances.removeValue(forKey: key)
            lru.forget(key)
        }
    }

    private func evictLeastRecentlyUsedIfNeeded(maxCached: Int) {
        guard instances.count >= maxCached else { return }

        if let oldest = lru.leastRecentlyUsed() {
            instances.removeValue(forKey: oldest)
            lru.forget(oldest)
        }
    }

    private func isModelDownloadedLocally(_ model: WhisperModel) async -> Bool {
        WhisperKitStorage.isModelDownloaded(model)
    }

    private func getLocalModelPath(for model: WhisperModel) -> String? {
        WhisperKitStorage.localModelPath(for: model)
    }
}

internal final class LocalWhisperService: Sendable {
    static let shared = LocalWhisperService()

    /// Default model used when the stored `selectedWhisperModel` value is missing
    /// or doesn't match a known `WhisperModel` case. Mirrors `AppDefaults.selectedWhisperModel`.
    static let defaultModel: WhisperModel = .base

    /// Reads the persisted `selectedWhisperModel` and returns a `WhisperModel`,
    /// falling back to `defaultModel` if the stored value is empty or no longer
    /// matches a known enum case. Delegates to `AppDefaults.selectedWhisperModel`,
    /// which already validates against the enum and falls back to `.base`
    /// (== `defaultModel`).
    static var safeSelectedWhisperModel: WhisperModel {
        AppDefaults.selectedWhisperModel
    }

    // Use actor isolation for thread-safe access to mutable state
    private let cache = WhisperKitCache()
    private let maxCachedModels = 3 // Limit cache to prevent excessive memory usage
    private let memoryPressureSource: DispatchSourceMemoryPressure?

    enum MemoryPressureAction { case none, keepMostRecent, clearAll }

    static func cacheAction(for event: DispatchSource.MemoryPressureEvent) -> MemoryPressureAction {
        if event.contains(.critical) { return .clearAll }
        if event.contains(.warning) { return .keepMostRecent }
        return .none
    }

    init() {
        // Create memory pressure source inline to avoid self reference
        let queue = DispatchQueue(label: "whisperkit.memorypressure")
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)

        // Capture cache reference for use in the event handler
        // The cache is an actor (reference type), so we capture it directly.
        // Since LocalWhisperService owns the cache and source, the lifecycle is properly managed.
        let cacheRef = cache

        source.setEventHandler {
            let memoryPressure = source.data

            if Self.cacheAction(for: memoryPressure) == .clearAll {
                // Critical memory pressure - clear all cached models
                Task {
                    await cacheRef.clear()
                }
            } else if Self.cacheAction(for: memoryPressure) == .keepMostRecent {
                // Warning level - remove least recently used models aggressively
                Task {
                    await cacheRef.clearExceptMostRecent()
                }
            }
        }

        source.resume()
        self.memoryPressureSource = source
    }

    deinit {
        memoryPressureSource?.cancel()
    }

    func transcribe(
        audioFileURL: URL,
        model: WhisperModel,
        prompt: String? = nil,
        language: DictationLanguage = .automatic,
        progressCallback: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        // Get or create WhisperKit instance from actor-isolated cache.
        // Audit item B3: cache is keyed by the typed `WhisperModel`; the raw
        // model name is only used internally when constructing `WhisperKitConfig`.
        let whisperKit = try await cache.getOrCreate(model: model, maxCached: maxCachedModels, progressCallback: progressCallback)

        // Provide helpful progress messaging with duration estimate
        let durationHint = getDurationHint(for: model)
        progressCallback?("Transcribing audio... \(durationHint)")

        // Transcribe the audio file. Incremental loading already cuts the file
        // at silences (VADAudioChunker) into model-sized windows, so long
        // recordings never decode across a 30 s seam.
        progressCallback?("Processing audio...")
        let results = try await whisperKit.transcribe(
            audioPath: audioFileURL.path,
            audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
            decodeOptions: Self.decodingOptions(prompt: prompt, tokenizer: whisperKit.tokenizer, language: language))

        // Combine all transcription segments into a single text
        let transcription = results.map { $0.text }.joined(separator: " ")

        guard !transcription.isEmpty else {
            throw LocalWhisperError.transcriptionFailed
        }
        if let prompt, Self.isPromptEcho(transcription, prompt: prompt) {
            throw SpeechToTextError.noSpeechDetected
        }

        progressCallback?("Transcription complete!")
        return transcription.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    /// Transcription (X→X, never translation) with the language auto-detected.
    func meetingSegments(
        audioFileURL: URL, model: WhisperModel, language: DictationLanguage,
        source: MeetingAudioSource, offset: TimeInterval
    ) async throws -> [MeetingSegment] {
        let engine = try await cache.getOrCreate(model: model, maxCached: maxCachedModels, progressCallback: nil)
        var options = Self.decodingOptions(prompt: nil, tokenizer: engine.tokenizer, language: language)
        options.wordTimestamps = true
        options.skipSpecialTokens = true
        let results = try await engine.transcribe(audioPath: audioFileURL.path, decodeOptions: options)
        try Task.checkCancellation()
        return results.flatMap(\.segments).compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return MeetingSegment(source: source, start: offset + Double(segment.start),
                                  end: offset + Double(segment.end), text: text)
        }
    }

    /// Explicit language is supported by Whisper; it still transcribes rather than translating.
    static func decodingOptions(
        prompt: String?, tokenizer: WhisperTokenizer?, language: DictationLanguage = .automatic
    ) -> DecodingOptions {
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = language == .automatic ? nil : language.rawValue
        if let prompt, let tokenizer {
            options.promptTokens = promptTokens(
                for: prompt, encode: { tokenizer.encode(text: $0) },
                specialTokenBegin: tokenizer.specialTokens.specialTokenBegin)
        }
        return options
    }

    /// Whisper conditions on preceding text, so the user's spellings supplied
    /// as "previous context" pull decoding toward them. Special tokens would be
    /// read as control codes and are dropped, as WhisperKit's own CLI does.
    static func promptTokens(for prompt: String, encode: (String) -> [Int], specialTokenBegin: Int) -> [Int]? {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let tokens = encode(" " + text).filter { $0 < specialTokenBegin }
        return tokens.isEmpty ? nil : tokens
    }

    /// A prompted decoder can answer near-silence by repeating its prompt.
    /// That is not something the user said.
    static func isPromptEcho(_ transcription: String, prompt: String) -> Bool {
        let normalize: (String) -> String = {
            $0.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        let spoken = normalize(transcription)
        return !spoken.isEmpty && spoken == normalize(prompt)
    }

    /// Locale-independent network-failure detection: inspects the error type
    /// and domain rather than locale-/version-fragile localized message text.
    /// Used to map a WhisperKit construction failure caused by a network fetch
    /// to `modelNotDownloaded`.
    static func isNetworkError(_ error: Error) -> Bool {
        if error is URLError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        // Walk a wrapped underlying error if present.
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isNetworkError(underlying)
        }
        return false
    }

    // Method to clear cached instances if needed (for memory management)
    func clearCache() async {
        await cache.clear()
    }

    /// Reload the on-disk assets, rather than validating a previously cached
    /// instance after an installation or repair.
    func verifyModel(_ model: WhisperModel) async throws {
        await cache.clear()
        _ = try await cache.getOrCreate(model: model, maxCached: maxCachedModels, progressCallback: nil)
    }

    // Provide helpful duration hints based on model speed
    private func getDurationHint(for model: WhisperModel) -> String {
        switch model {
        case .tiny:
            return "This may take 30-60 seconds..."
        case .base:
            return "This may take 1-2 minutes..."
        case .small:
            return "This may take 2-3 minutes..."
        case .largeTurbo:
            return "This may take 3-5 minutes..."
        }
    }
}

internal enum LocalWhisperError: LocalizedError {
    case modelNotDownloaded
    case invalidAudioFile
    case bufferAllocationFailed
    case noChannelData
    case resamplingFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotDownloaded:
            return "Whisper model not downloaded. Please download the model in Settings before using offline transcription."
        case .invalidAudioFile:
            return "Invalid audio file format"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .noChannelData:
            return "No audio channel data found"
        case .resamplingFailed:
            return "Failed to resample audio"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
