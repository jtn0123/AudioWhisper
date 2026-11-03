import AppKit
import Observation

@MainActor
@Observable
final class DiagnosticController {
    static let shared = DiagnosticController(store: DiagnosticStore(
        file: AppEnvironment.isRunningTests ? nil
            : RebuildStorage.root.appendingPathComponent("Diagnostics/recent-v1.json")))
    let store: DiagnosticStore
    private var pending: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var spaceObserver: NSObjectProtocol?

    init(store: DiagnosticStore) {
        self.store = store
        guard !AppEnvironment.isRunningTests else { return }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                NSApp.windows.filter { $0.isVisible }.forEach { self?.window(.spaceChanged, $0) }
            }
        }
    }

    deinit {
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    static var enabled: Bool {
        get { AppDefaults.defaults.object(forKey: "diagnostics.historyEnabled") as? Bool ?? true }
        set { AppDefaults.defaults.set(newValue, forKey: "diagnostics.historyEnabled") }
    }

    static var detailed: Bool {
        get { AppDefaults.defaults.bool(forKey: "diagnostics.resourceSampling") }
        set { AppDefaults.defaults.set(newValue, forKey: "diagnostics.resourceSampling") }
    }

    func start(_ config: TranscriptionPipelineConfig, id: UUID, entry: DiagnosticEntry, mode: UUID?) -> DiagnosticTrace? {
        guard Self.enabled else { return nil }
        let model = config.provider == .local ? config.whisperModel?.rawValue : config.parakeetModel?.rawValue
        return DiagnosticTrace(record: .init(id: id, started: Date(), finished: Date(), build: VersionInfo.gitHash,
            system: ProcessInfo.processInfo.operatingSystemVersionString, architecture: Arch.isAppleSilicon ? "arm64" : "x86_64",
            entry: entry, provider: config.provider.rawValue, voiceModel: DiagnosticRecord.modelIdentifier(model) ?? "unknown",
            writingModel: config.applySemanticCorrection ? DiagnosticRecord.modelIdentifier(config.correctionModelRepo) : nil,
            modeID: mode, preferredInput: !AppDefaults.selectedMicrophone.isEmpty,
            outcome: .completed, delivery: .none, spans: [], resources: []))
    }

    func finish(_ trace: DiagnosticTrace?, outcome: DiagnosticOutcome, delivery: DiagnosticDelivery = .none) {
        guard let record = trace?.finish(outcome, delivery: delivery), Self.enabled else { return }
        let previous = pending
        pending = Task { [store] in await previous?.value; await store.append(record) }
    }

    func window(_ action: DiagnosticWindowEvent.Action, _ window: NSWindow) {
        guard Self.enabled, !AppEnvironment.isRunningTests else { return }
        let event = DiagnosticWindowEvent(date: Date(), action: action, build: VersionInfo.gitHash,
            windowNumber: window.windowNumber, level: window.level.rawValue, behavior: window.collectionBehavior.rawValue,
            applicationPolicy: NSApp.activationPolicy().rawValue, applicationActive: NSApp.isActive,
            systemFullScreen: NSApp.currentSystemPresentationOptions.contains(.fullScreen), visible: window.isVisible,
            key: window.isKeyWindow, onActiveSpace: window.isOnActiveSpace,
            frame: [window.frame.minX, window.frame.minY, window.frame.width, window.frame.height])
        let previous = pending
        pending = Task { [store] in await previous?.value; await store.append(event) }
    }

    func snapshot() async -> DiagnosticArchive { await pending?.value; return await store.snapshot() }
    func export() async throws -> Data { await pending?.value; return try await store.export() }
    func clear() async throws { await pending?.value; try await store.clear() }
}
