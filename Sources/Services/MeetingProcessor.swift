import Foundation
import SpeakerKit
import WhisperKit
import ArgmaxCore

struct MeetingProcessingOptions: Sendable {
    var model: WhisperModel
    var language: DictationLanguage = .automatic
    var speakerModelFolder: String?
    var summarize = false
    var summaryModel: String
    var keepAudio = false
}

@MainActor
struct MeetingProcessingServices {
    var modelInstalled: (WhisperModel) -> Bool
    var transcribe: (URL, WhisperModel, DictationLanguage, MeetingAudioSource, TimeInterval) async throws -> [MeetingSegment]
    var clearVoiceCache: () async -> Void
    var speakers: (MeetingDocument, String) async throws -> [MeetingSegment]
    var summaryReady: (String) async -> Bool
    var summarize: (String, String) async throws -> String
    var shutdown: () async -> Void = {}

    static func live(store: MeetingStore) -> Self {
        let summary = MeetingSummaryWorker()
        return .init(modelInstalled: { WhisperKitStorage.isModelDownloaded($0) }, transcribe: {
            try await LocalWhisperService.shared.meetingSegments(
                audioFileURL: $0, model: $1, language: $2, source: $3, offset: $4)
        }, clearVoiceCache: { await LocalWhisperService.shared.clearCache() }, speakers: {
            try await MeetingProcessor.speakers($0, folder: $1, store: store)
        }, summaryReady: { repo in
            guard Arch.isAppleSilicon, await UvBootstrap.isEnvReady() else { return false }
            return MLXModelManager.shared.isModelCachedOnDisk(repo: repo)
        }, summarize: { try await summary.summarize(text: $0, repo: $1) }, shutdown: { await summary.shutdown() })
    }
}

@MainActor
struct MeetingProcessor {
    let store: MeetingStore
    let services: MeetingProcessingServices

    init(store: MeetingStore, services: MeetingProcessingServices? = nil) {
        self.store = store
        self.services = services ?? .live(store: store)
    }

    func process(
        _ original: MeetingDocument, options: MeetingProcessingOptions,
        progress: @escaping (MeetingDocument, String) -> Void
    ) async throws -> MeetingDocument {
        do {
            let result = try await perform(original, options: options, progress: progress)
            await services.shutdown()
            return result
        } catch {
            await services.shutdown()
            throw error
        }
    }

    private func perform(
        _ original: MeetingDocument, options: MeetingProcessingOptions,
        progress: @escaping (MeetingDocument, String) -> Void
    ) async throws -> MeetingDocument {
        guard services.modelInstalled(options.model) else { throw MeetingError.model }
        guard !original.chunks.isEmpty, original.audioRetained else { throw MeetingError.audio }
        var document = original
        document.segments = []
        document.summary = nil
        document.note = nil
        document.status = .processing
        for (index, chunk) in document.chunks.sorted(by: { $0.offset < $1.offset }).enumerated() {
            try Task.checkCancellation()
            if chunk.hasSignal == false { continue }
            let audio = try store.audioURL(document.id, filename: chunk.filename)
            let segments = try await services.transcribe(audio, options.model, options.language, chunk.source, chunk.offset)
            document.segments += segments
            try store.save(document)
            progress(document, "Transcribed chunk \(index + 1) of \(document.chunks.count)")
        }
        await services.clearVoiceCache()
        guard !document.segments.isEmpty else { throw SpeechToTextError.noSpeechDetected }
        if let folder = options.speakerModelFolder {
            progress(document, "Estimating speaker clusters locally…")
            document.segments = try await services.speakers(document, folder)
            try store.save(document)
        }
        if options.summarize {
            progress(document, "Preparing local meeting notes…")
            guard await services.summaryReady(options.summaryModel) else {
                throw PublicAutomationError.assets
            }
            document.summary = try await summarize(document.transcript, repo: options.summaryModel)
        }
        try Task.checkCancellation()
        document.status = .complete
        try store.save(document)
        if !options.keepAudio { try store.removeAudio(&document) }
        return document
    }

    static func speakers(_ document: MeetingDocument, folder: String, store: MeetingStore) async throws -> [MeetingSegment] {
        let config = PyannoteConfig(
            modelDownloadConfig: ModelDownloadConfig(modelRepo: "argmaxinc/speakerkit-coreml", modelFolder: folder),
            download: false, verbose: false, concurrentSegmenterWorkers: 1, concurrentEmbedderWorkers: 1)
        let engine = try await SpeakerKit(config)
        do {
            var segments = document.segments
            for source in MeetingAudioSource.allCases {
                let chunks = document.chunks.filter { $0.source == source }
                guard !chunks.isEmpty else { continue }
                let samples = try await trackSamples(document.id, chunks: chunks, store: store)
                let result = try await engine.diarize(audioArray: samples)
                for index in segments.indices where segments[index].source == source {
                    segments[index].speaker = Self.speakerLabel(start: segments[index].start, end: segments[index].end,
                        spans: result.segments.map {
                            MeetingSpeakerSpan(start: Double($0.startTime), end: Double($0.endTime),
                                               label: $0.speaker.description)
                        })
                }
            }
            await engine.unloadModels()
            return segments
        } catch { await engine.unloadModels(); throw error }
    }

    static func speakerLabel(start: Double, end: Double, spans: [MeetingSpeakerSpan]) -> String {
        let labels = Set(spans.filter { min(end, $0.end) - max(start, $0.start) > 0.02 }.map(\.label))
        if labels.count == 1 { return labels.first ?? "Unknown speaker" }
        return labels.isEmpty ? "Unknown speaker" : "Multiple speakers"
    }

    private static func trackSamples(_ id: UUID, chunks: [MeetingAudioChunk], store: MeetingStore) async throws -> [Float] {
        let urls = try chunks.map { (try store.audioURL(id, filename: $0.filename), $0.offset) }
        return try await Task.detached(priority: .utility) {
            var track: [Float] = []
            for (url, offset) in urls {
                try Task.checkCancellation()
                let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
                let start = Int(offset * 16_000)
                guard start >= 0, start + samples.count <= 1_805 * 16_000 else { throw MeetingError.bounds }
                if track.count < start + samples.count {
                    track += Array(repeating: 0, count: start + samples.count - track.count)
                }
                track.replaceSubrange(start..<(start + samples.count), with: samples)
            }
            return track
        }.value
    }

    private func summarize(_ text: String, repo: String) async throws -> String {
        guard text.count <= 256_000 else { throw MeetingError.bounds }
        var level = Self.summaryChunks(text)
        for _ in 0..<5 {
            var summaries: [String] = []
            for chunk in level {
                try Task.checkCancellation()
                summaries.append(try await services.summarize(chunk, repo))
            }
            if summaries.count == 1 { return summaries[0] }
            level = Self.summaryChunks(summaries.joined(separator: "\n\n"))
        }
        throw MeetingError.bounds
    }

    static func summaryChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        let scalars = text.unicodeScalars
        var start = scalars.startIndex
        while start < scalars.endIndex {
            var end = scalars.index(start, offsetBy: 8_000, limitedBy: scalars.endIndex) ?? scalars.endIndex
            if end < scalars.endIndex, let boundary = scalars[start..<end].lastIndex(where: { $0 == "\n" || $0 == " " }),
               scalars.distance(from: start, to: boundary) >= 4_000 { end = scalars.index(after: boundary) }
            chunks.append(String(scalars[start..<end]))
            start = end
        }
        return chunks
    }
}

@MainActor
private final class MeetingSummaryWorker {
    private var daemon: MLDaemonManager?
    func summarize(text: String, repo: String) async throws -> String {
        if daemon == nil {
            let python = try await UvBootstrap.installedPython()
            try Task.checkCancellation()
            daemon = MLDaemonManager(pythonExecutable: python, allowsRuntimePreparation: false)
        }
        guard let daemon else { throw PublicAutomationError.assets }
        return try await daemon.summarize(repo: repo, text: text)
    }
    func shutdown() async {
        await daemon?.shutdown()
        daemon = nil
    }
}
