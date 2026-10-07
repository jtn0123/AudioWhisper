import Observation

@MainActor
struct RebuildWritingOperations {
    var verify: (String) async throws -> ModelVerificationResult
    var remove: (String) async -> Void
    var isCached: (String) -> Bool

    static var live: Self {
        Self(verify: { selected in
            let python = try await UvBootstrap.ensureVenv()
            return try await ModelVerificationService.verify(
                scriptName: "verify_mlx", arguments: [selected] + ModelPins.scriptArguments(for: selected),
                pythonPath: python.path, successFallback: "Correction model is ready")
        }, remove: { await MLXModelManager.shared.deleteModel($0) },
             isCached: { MLXModelManager.shared.isModelCachedOnDisk(repo: $0) })
    }
}

/// Observable operation state lets controls reflect the real async work,
/// including maintenance admission and terminal failures.
@MainActor
@Observable
final class RebuildWritingMaintenance {
    enum Action { case verifying, removing }
    private(set) var action: Action?
    var status: RebuildWritingStatus?
    var confirmRemoval = false
    private let operations: RebuildWritingOperations

    init(operations: RebuildWritingOperations? = nil) { self.operations = operations ?? .live }

    func verify(_ selected: String, session: RebuildSession) async {
        guard begin(.verifying, session: session) else { return }
        defer { action = nil; session.maintenanceInProgress = false }
        do { status = .verification(try await operations.verify(selected)) } catch { status = .failure(error) }
    }

    func remove(_ selected: String, session: RebuildSession) async {
        guard begin(.removing, session: session) else { return }
        defer { action = nil; session.maintenanceInProgress = false }
        AppDefaults.semanticCorrectionMode = .off
        await operations.remove(selected)
        status = .removal(stillOnDisk: operations.isCached(selected))
    }

    private func begin(_ action: Action, session: RebuildSession) -> Bool {
        guard self.action == nil, !session.phase.isBusy, !session.isInstalling,
              !session.maintenanceInProgress else { return false }
        self.action = action
        session.maintenanceInProgress = true
        status = nil
        return true
    }
}
