import Foundation
import Observation

@Observable
@MainActor
final class RebuildWritingInstaller {
    private let manager: MLXModelManager
    private var task: Task<Void, Never>?
    private(set) var repo: String?
    private(set) var status: String?
    private(set) var cancelling = false

    init(manager: MLXModelManager? = nil) { self.manager = manager ?? .shared }
    var isRunning: Bool { repo != nil }
    var progress: String? { repo.flatMap { manager.downloadProgress[$0] } }
    var fraction: Double? { repo.flatMap { manager.downloadFraction[$0] } }

    func start(_ selected: String, session: RebuildSession) {
        guard !isRunning, !session.phase.isBusy, !session.isInstalling, !session.maintenanceInProgress else { return }
        repo = selected
        status = nil
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
                    ? "Installed. You can enable cleanup now." : "Installation did not finish. Please retry.")
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
