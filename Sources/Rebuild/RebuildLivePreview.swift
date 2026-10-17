import Foundation
import Observation

/// Display-only, rolling recognition. Final transcription still owns delivery.
/// A single inference may outlive cancellation; its generation cannot update a
/// stopped/replaced session, and its file remains leased until the daemon finishes.
@MainActor
@Observable
final class RebuildLivePreview {
    private(set) var text = ""
    private(set) var enabled = false
    private(set) var updating = false
    private(set) var paused = false
    private(set) var message = "Listening for speech…"
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var inferenceInFlight = false
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private let recognize: @Sendable (RecordingPreviewSnapshot, ParakeetModel) async throws -> String

    init(
        interval: Duration = .seconds(2),
        recognize: @escaping @Sendable (RecordingPreviewSnapshot, ParakeetModel) async throws -> String = { audio, model in
            let pcm = try audio.writePCM()
            return try await ParakeetService.shared.transcribePreparedPCM(pcm, repo: model.rawValue)
        }
    ) {
        self.interval = interval
        self.recognize = recognize
    }

    func start(model: ParakeetModel, snapshot: @escaping @MainActor () async -> RecordingPreviewSnapshot?) {
        stop(clear: true)
        enabled = true
        paused = false
        message = "Listening for speech…"
        let id = UUID()
        generation = id
        let interval = self.interval
        job = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard let self, generation == id, !Task.isCancelled else { return }
                guard !inferenceInFlight, let audio = await snapshot() else { continue }
                guard generation == id, !Task.isCancelled else { return }
                inferenceInFlight = true
                updating = true
                let recognize = self.recognize
                let worker = Task.detached(priority: .utility) { try await recognize(audio, model) }
                let result = await worker.result
                inferenceInFlight = false
                guard generation == id, !Task.isCancelled else { return }
                updating = false
                switch result {
                case .success(let draft):
                    let cleaned = SpeechToTextService.cleanTranscriptionText(draft)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !cleaned.isEmpty { text = cleaned }
                case .failure:
                    paused = true
                    message = "Preview paused. Your recording will still be transcribed."
                    return
                }
            }
        }
    }

    deinit { job?.cancel() }

    func stop(clear: Bool = false) {
        generation = nil
        job?.cancel()
        job = nil
        updating = false
        if clear { text = ""; enabled = false }
    }
}
