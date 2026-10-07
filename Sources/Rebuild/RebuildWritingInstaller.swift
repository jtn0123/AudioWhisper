import Observation

@Observable
@MainActor
final class RebuildWritingInstaller {
    private let manager: MLXModelManager
    private var task: Task<Void, Never>?
    private(set) var repo: String?
    private(set) var status: String?
    private var statusRepo: String?
    private(set) var cancelling = false

    static let installedMessage = "Installed. You can enable cleanup now."

    init(manager: MLXModelManager? = nil) { self.manager = manager ?? .shared }
    var isRunning: Bool { repo != nil }
    var progress: String? { repo.flatMap { manager.downloadProgress[$0] } }
    var fraction: Double? { repo.flatMap { manager.downloadFraction[$0] } }

    func status(for selected: String) -> String? { statusRepo == selected ? status : nil }

    func start(_ selected: String, session: RebuildSession) {
        guard !isRunning, !session.phase.isBusy, !session.isInstalling, !session.maintenanceInProgress else { return }
        repo = selected
        status = nil
        statusRepo = nil
        cancelling = false
        session.maintenanceInProgress = true
        task = Task {
            defer {
                session.maintenanceInProgress = false
                repo = nil
                cancelling = false
                task = nil
            }
            await manager.downloadModel(selected)
            status = manager.downloadProgress[selected]
                ?? (manager.isModelCachedOnDisk(repo: selected)
                    ? Self.installedMessage : "Installation did not finish. Please retry.")
            statusRepo = selected
        }
    }

    func cancel() async {
        guard let repo, !cancelling else { return }
        cancelling = true
        task?.cancel()
        await manager.cancelDownload(repo)
        await task?.value
    }
}
