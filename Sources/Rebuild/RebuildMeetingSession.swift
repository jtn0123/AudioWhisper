import Foundation
import Observation

@MainActor
@Observable
final class RebuildMeetingSession {
    enum Activity { case idle, starting, capturing, stopping, processing }
    typealias Process = (MeetingDocument, MeetingProcessingOptions, @escaping (MeetingDocument, String) -> Void)
        async throws -> MeetingDocument
    var title = ""
    var microphone = true
    var systemAudio = true
    var keepAudio = false
    var makeSummary = false
    var voiceModel = AppDefaults.selectedWhisperModel
    var speakerModelFolder: String?
    private(set) var activity: Activity = .idle
    private(set) var document: MeetingDocument?
    private(set) var documents: [MeetingListEntry] = []
    private(set) var inventoryNotice: String?
    private(set) var progress = ""
    var error: String?
    private weak var dictation: RebuildSession?
    let store: MeetingStore
    private let capture: MeetingCapturing
    private let process: Process
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var limit: Task<Void, Never>?
    private var ownsMaintenance = false

    init(dictation: RebuildSession?, store: MeetingStore = MeetingStore(), capture: MeetingCapturing? = nil,
         process: Process? = nil) {
        self.dictation = dictation
        self.store = store
        self.capture = capture ?? MeetingNativeCapture()
        self.process = process ?? { try await MeetingProcessor(store: store).process($0, options: $1, progress: $2) }
    }

    var busy: Bool { activity != .idle }
    var canStart: Bool {
        !busy && (microphone || systemAudio) && dictation?.phase.isBusy != true
            && dictation?.maintenanceInProgress != true && dictation?.isInstalling != true
    }

    func refresh() {
        do {
            let inventory = try store.list()
            documents = inventory.entries.map { stored in
                if let document, document.id == stored.id { return MeetingListEntry(document) }
                return stored
            }
            var notices: [String] = []
            if inventory.unreadableCount > 0 {
                notices.append("\(inventory.unreadableCount) meeting folders could not be read. Their files have been kept.")
            }
            if inventory.hasMore { notices.append("Showing the 100 most recent meeting folders.") }
            inventoryNotice = notices.isEmpty ? nil : notices.joined(separator: " ")
        } catch { self.error = error.localizedDescription }
    }

    func open(_ id: UUID) {
        guard !busy else { return }
        do { document = try store.load(id); error = nil } catch { self.error = error.localizedDescription }
    }

    private func reserve() throws {
        guard dictation?.phase.isBusy != true, dictation?.maintenanceInProgress != true,
              dictation?.isInstalling != true else { throw MeetingError.busy }
        dictation?.maintenanceInProgress = true
        dictation?.maintenanceLabel = "Meeting in progress"
        ownsMaintenance = true
    }

    private func release() {
        guard ownsMaintenance else { return }
        dictation?.maintenanceInProgress = false
        dictation?.maintenanceLabel = nil
        ownsMaintenance = false
    }

    func start() {
        guard canStart else { return }
        do {
            try reserve()
            let document = MeetingDocument(title: title)
            try store.save(document)
            self.document = document
            activity = .starting
            error = nil
            progress = "Requesting capture access…"
            startCapture(document.id)
        } catch { release(); self.error = error.localizedDescription }
    }

    private func startCapture(_ id: UUID) {
        let microphone = self.microphone, system = systemAudio
        job = Task { [weak self] in
            guard let self else { return }
            do {
                try await capture.start(folder: store.folder(id), microphone: microphone, system: system,
                    closed: { [weak self] chunk in Task { @MainActor in self?.closed(chunk, id: id) } },
                    failed: { [weak self] message in Task { @MainActor in
                        guard self?.document?.id == id else { return }
                        await self?.stop(reason: message)
                    } })
                guard !Task.isCancelled, document?.id == id, activity == .starting else { return }
                activity = .capturing
                progress = "Recording meeting audio · 30 minute limit"
                limit = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(1_800)) } catch { return }
                    await self?.stop(reason: MeetingError.bounds.localizedDescription)
                }
            } catch {
                guard document?.id == id, activity == .starting else { return }
                document?.status = .failed
                document?.note = error.localizedDescription
                if let document { try? store.save(document) }
                self.error = error.localizedDescription
                activity = .idle
                release()
                refresh()
            }
        }
    }

    private func closed(_ chunk: MeetingAudioChunk, id: UUID) {
        guard var document, document.id == id, !document.chunks.contains(where: { $0.id == chunk.id }) else { return }
        document.chunks.append(chunk)
        self.document = document
        do { try store.save(document) } catch {
            self.error = "Meeting manifest could not be saved: " + error.localizedDescription
            Task { [weak self] in
                guard self?.document?.id == id else { return }
                await self?.stop(reason: "Storage failed. Source audio has been kept.")
            }
        }
    }

    func stop(reason: String? = nil) async {
        guard activity == .starting || activity == .capturing else { return }
        activity = .stopping
        job?.cancel()
        limit?.cancel()
        limit = nil
        let chunks = await capture.stop()
        if var document {
            for chunk in chunks where !document.chunks.contains(where: { $0.id == chunk.id }) { document.chunks.append(chunk) }
            document.status = reason == nil ? .captured : .interrupted
            document.note = reason
            if document.chunks.isEmpty { document.status = .failed; document.note = "No usable audio was captured." }
            self.document = document
            do { try store.save(document) } catch { self.error = error.localizedDescription }
        }
        activity = .idle
        progress = "Audio kept on this Mac. Process when ready."
        release()
        refresh()
    }

    func processCurrent() {
        guard !busy, let document, document.audioRetained else { return }
        do { try reserve() } catch { self.error = error.localizedDescription; return }
        let options = MeetingProcessingOptions(model: voiceModel, language: AppDefaults.dictationLanguage,
            speakerModelFolder: speakerModelFolder, summarize: makeSummary,
            summaryModel: AppDefaults.semanticCorrectionModelRepo, keepAudio: keepAudio)
        activity = .processing
        error = nil
        progress = "Preparing local processing…"
        job = Task { [weak self] in
            guard let self else { return }
            defer { activity = .idle; release(); refresh() }
            do {
                let result = try await process(document, options) { [weak self] updated, message in
                    guard !Task.isCancelled, self?.document?.id == updated.id else { return }
                    self?.document = updated
                    self?.progress = message
                }
                // A completed manifest/audio-retention commit survives cancellation during worker cleanup.
                guard !Task.isCancelled || result.status == .complete else { throw CancellationError() }
                self.document = result
                progress = "Meeting transcript ready. Review estimated speakers and notes before using them."
            } catch {
                self.document?.status = error is CancellationError ? .interrupted : .failed
                self.document?.note = "Processing stopped. Transcript and source audio were kept: " + error.localizedDescription
                if let document = self.document { try? store.save(document) }
                self.error = self.document?.note
            }
        }
    }

    func cancelProcessing() { job?.cancel(); progress = "Cancelling local processing…" }

    func deleteCurrent() {
        guard !busy, let document else { return }
        do { try store.delete(document.id); self.document = nil; refresh() } catch { self.error = error.localizedDescription }
    }

    func shutdown() async {
        limit?.cancel()
        if activity == .processing {
            job?.cancel()
            await job?.value
        } else { await stop(reason: "AudioWhisper quit before processing. Audio was kept.") }
    }
}
