import Foundation

@MainActor
struct RebuildSessionServices {
    var start: (UUID) -> Bool
    var stop: () -> URL?
    var cancel: () -> Void
    var transcribe: (URL, TranscriptionPipelineConfig, UUID) async throws -> TranscriptionResult
    var copy: (String) -> Void
    var save: (String, TranscriptionPipelineConfig, TimeInterval?) async throws -> Void
    var interruptionSource: NSObject?
    var announce: (String) -> Void = RebuildAnnouncements.post
    var contextCapture = RebuildWritingContextCapture()
    var capturePasteDestination: () -> RebuildPasteDestination? = { .capture() }
    var startError: () -> String? = { nil }
    var startAsync: ((UUID) async -> Bool)?
    var saveResult: ((TranscriptionResult, TranscriptionPipelineConfig, TimeInterval?) async throws -> Void)?
    var recordedSignal: () -> RecordingSignalMeter? = { nil }
    var configureLivePreview: (Bool) -> Void = { _ in
        // Services without a live recorder have no preview audio buffer to configure.
    }
    var previewSnapshot: () async -> RecordingPreviewSnapshot? = { nil }
    /// Present when the user wants their clipboard back after Smart Paste.
    var clipboardKeeper: () -> ClipboardKeeper? = { AppDefaults.restoreClipboardAfterPaste ? ClipboardKeeper() : nil }

    static func live(
        recorder: AudioEngineRecorder,
        pipeline: TranscriptionPipeline? = nil,
        copy: ((String) -> Void)? = nil,
        history: DataManagerProtocol? = nil,
        usage: UsageMetricsStore? = nil
    ) -> Self {
        let pipeline = pipeline ?? TranscriptionPipeline()
        let history = history ?? DataManager.shared
        let usage = usage ?? UsageMetricsStore.shared
        return Self(
            start: { id in
                PermissionManager.shared.checkPermissionState()
                return recorder.startRecording(sessionID: id)
            }, stop: { recorder.stopRecording() }, cancel: { recorder.cancelRecording() },
            transcribe: { url, config, id in
                try await runTranscription(url, config: config, id: id, pipeline: pipeline)
            },
            copy: copy ?? PasteManager.copyToClipboard,
            save: { text, config, duration in
                try await persist(
                    TranscriptionResult(text: text, correctionOutcome: nil), config: config,
                    duration: duration, history: history, usage: usage)
            },
            interruptionSource: recorder,
            startError: { recorder.lastStartError },
            startAsync: { id in
                PermissionManager.shared.checkPermissionState()
                return await recorder.startRecordingAsync(sessionID: id)
            },
            saveResult: { result, config, duration in
                try await persist(result, config: config, duration: duration, history: history, usage: usage)
            },
            recordedSignal: { recorder.lastRecordingSignal },
            configureLivePreview: { recorder.livePreviewEnabled = $0 },
            previewSnapshot: {
                guard recorder.isRecording else { return nil }
                let buffer = recorder.previewAudio
                return await Task.detached(priority: .utility) { buffer.snapshot() }.value
            }
        )
    }

    private static func runTranscription(
        _ url: URL, config: TranscriptionPipelineConfig, id: UUID, pipeline: TranscriptionPipeline
    ) async throws -> TranscriptionResult {
        try await TranscriptionProgress.$sessionID.withValue(id) {
            try await TranscriptionProgress.$pipelineConfig.withValue(config) {
                try await pipeline.transcribe(audioURL: url, config: config)
            }
        }
    }

    private static func persist(
        _ result: TranscriptionResult, config: TranscriptionPipelineConfig, duration: TimeInterval?,
        history: DataManagerProtocol, usage: UsageMetricsStore
    ) async throws {
        let count = UsageMetricsStore.estimatedWordCount(for: result.text)
        usage.recordSession(duration: duration, wordCount: count, characterCount: result.text.count)
        guard AppDefaults.transcriptionHistoryEnabled else { return }
        try await history.saveTranscription(
            TranscriptionRecord(
                text: result.text, provider: config.provider, duration: duration,
                modelUsed: config.provider == .local
                    ? config.whisperModel?.rawValue : config.parakeetModel?.rawValue,
                wordCount: count, characterCount: result.text.count, sourceAppBundleId: config.sourceAppBundleId,
                originalText: result.originalText == result.text ? nil : result.originalText))
    }
}
