import Foundation
import Observation

@MainActor
@Observable
final class RebuildHistoryCleanup {
    let recordID: UUID
    let original: String
    let history: DataManagerProtocol
    let session: RebuildSession?
    var selectedMode = "current"
    var result: String?
    var error: String?
    var running = false
    var saved = false
    private var version: TranscriptionCleanupVersion?
    @ObservationIgnored private var task: Task<Void, Never>?
    private let cleanup: (String, TranscriptionPipelineConfig) async -> TranscriptionResult

    init(record: TranscriptionRecord, history: DataManagerProtocol, session: RebuildSession?,
         cleanup: ((String, TranscriptionPipelineConfig) async -> TranscriptionResult)? = nil) {
        recordID = record.id
        original = record.originalText ?? record.text
        self.history = history
        self.session = session
        let pipeline = TranscriptionPipeline()
        self.cleanup = cleanup ?? { await pipeline.cleanup(text: $0, config: $1) }
    }

    var blocked: Bool {
        running || session?.phase.isBusy == true || session?.maintenanceInProgress == true || session?.isInstalling == true
    }

    func run() {
        guard !blocked else { return }
        let mode = AppDefaults.savedDictationModes.first { $0.id.uuidString == selectedMode }
        var settings = mode?.settings ?? AppDefaults.currentDictationSettings
        guard settings.cleanup != .off else { error = "Choose a mode with local writing cleanup enabled."; return }
        guard original.count <= 20_000 else { error = HistoryCleanupError.oversized.localizedDescription; return }
        settings.writing.contextSource = .none
        let config = settings.pipeline()
        running = true
        session?.maintenanceInProgress = true
        error = nil
        result = nil
        version = nil
        saved = false
        task = Task { [weak self] in
            guard let self else { return }
            defer { running = false; session?.maintenanceInProgress = false }
            let outcome = await cleanup(original, config)
            guard !Task.isCancelled else { return }
            switch outcome.correctionOutcome {
            case .applied:
                result = outcome.text
                version = TranscriptionCleanupVersion(id: UUID(), createdAt: Date(), modeName: mode?.name ?? "Current settings",
                    text: outcome.text, writing: settings.writing, modelRepo: settings.cleanupModel)
            case .failed(let failure, _): error = "Writing cleanup failed: \(failure.localizedDescription)"
            default: error = "No safe writing change was produced. Your original is unchanged."
            }
        }
    }

    func save() async {
        guard !running, !saved, let version else { return }
        running = true
        defer { running = false }
        do {
            try await history.appendCleanupVersion(recordID: recordID, version: version)
            saved = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func cancel() { task?.cancel() }
}
