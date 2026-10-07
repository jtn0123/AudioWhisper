import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildWritingBehaviorTests: IsolatedXCTestCase {
    private func session() -> RebuildSession {
        RebuildSession(services: RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }))
    }

    func testVerificationButtonShowsBusyStateThenItsAuthoritativeOutcome() async throws {
        var pending: CheckedContinuation<ModelVerificationResult, Never>?
        var selected: String?
        let operations = RebuildWritingOperations(verify: {
            selected = $0
            return await withCheckedContinuation { pending = $0 }
        }, remove: { _ in XCTFail("Verification must not remove weights") }, isCached: { _ in true })
        let maintenance = RebuildWritingMaintenance(operations: operations)
        let session = session()
        let view = RebuildWritingView(session: session, isModelCached: { _ in true }, maintenance: maintenance)
        try view.inspect().find(button: "Verify correction model").tap()
        try await waitFor { pending != nil }
        XCTAssertEqual(selected, AppDefaults.semanticCorrectionModelRepo)
        XCTAssertTrue(session.maintenanceInProgress)
        XCTAssertTrue(try view.inspect().find(button: "Verifying…").isDisabled())
        XCTAssertTrue(try view.inspect().find(button: "Remove…").isDisabled())
        try XCTUnwrap(pending).resume(returning: ModelVerificationResult(succeeded: false, message: "Fixture invalid weights"))
        try await waitFor { maintenance.action == nil }
        _ = try view.inspect().find(text: "Fixture invalid weights")
        XCTAssertEqual(maintenance.status?.tone, .error)
        XCTAssertFalse(session.maintenanceInProgress)
    }

    func testThrownVerificationFailureKeepsCleanupPreferenceAndReleasesMaintenance() async throws {
        AppDefaults.semanticCorrectionMode = .localMLX
        let maintenance = RebuildWritingMaintenance(operations: RebuildWritingOperations(
            verify: { _ in throw NSError(domain: "fixture", code: 1,
                                        userInfo: [NSLocalizedDescriptionKey: "Fixture runtime failed"]) },
            remove: { _ in }, isCached: { _ in true }))
        let session = session()
        let view = RebuildWritingView(session: session, isModelCached: { _ in true }, maintenance: maintenance)
        try view.inspect().find(button: "Verify correction model").tap()
        try await waitFor { maintenance.status != nil }
        _ = try view.inspect().find(text: "Fixture runtime failed")
        XCTAssertEqual(maintenance.status?.tone, .error)
        XCTAssertEqual(AppDefaults.semanticCorrectionMode, .localMLX)
        XCTAssertFalse(session.maintenanceInProgress)
    }

    func testRemovalRequiresConfirmationAndTurnsCleanupOffOnlyAfterConfirming() async throws {
        AppDefaults.semanticCorrectionMode = .localMLX
        var removed: [String] = []
        var cached = true
        let maintenance = RebuildWritingMaintenance(operations: RebuildWritingOperations(
            verify: { _ in ModelVerificationResult(succeeded: true, message: "unused") },
            remove: { removed.append($0); cached = false }, isCached: { _ in cached }))
        let session = session()
        let view = RebuildWritingView(session: session, isModelCached: { _ in cached }, maintenance: maintenance)
        try view.inspect().find(button: "Remove…").tap()
        XCTAssertTrue(maintenance.confirmRemoval)
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(AppDefaults.semanticCorrectionMode, .localMLX)
        let dialog = try view.inspect().scrollView().confirmationDialog()
        try dialog.actions().find(button: "Remove model").tap()
        try await waitFor { !removed.isEmpty && maintenance.action == nil }
        XCTAssertEqual(removed, [AppDefaults.semanticCorrectionModelRepo])
        XCTAssertEqual(AppDefaults.semanticCorrectionMode, .off)
        _ = try view.inspect().find(text: "Correction model removed.")
        XCTAssertTrue(try view.inspect().find(ViewType.Toggle.self).isDisabled())
    }

    func testFailedRemovalIsReportedAndCannotRaceAnotherMaintenanceOperation() async throws {
        var removals = 0
        let maintenance = RebuildWritingMaintenance(operations: RebuildWritingOperations(
            verify: { _ in ModelVerificationResult(succeeded: true, message: "verified") },
            remove: { _ in removals += 1 }, isCached: { _ in true }))
        let session = session()
        session.maintenanceInProgress = true
        await maintenance.remove("fixture", session: session)
        await maintenance.verify("fixture", session: session)
        XCTAssertEqual(removals, 0)
        session.maintenanceInProgress = false
        await maintenance.remove("fixture", session: session)
        XCTAssertEqual(removals, 1)
        XCTAssertEqual(maintenance.status?.tone, .error)
        let view = RebuildWritingView(session: session, isModelCached: { _ in true }, maintenance: maintenance)
        _ = try view.inspect().find(text: "Removal failed. The model is still on disk.")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition())
    }
}

extension RebuildWritingBehaviorTests {
    func testInstallerProgressAndCancellationUseTheRealControlsWithoutDownloadingWeights() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon, "Writing installation requires Apple Silicon")
        var pending: CheckedContinuation<URL, Never>?
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("ui-progress-\(UUID())")
        let manager = MLXModelManager(cacheDirectory: cache, prepareDownloadPython: {
            await withCheckedContinuation { pending = $0 }
        })
        let installer = RebuildWritingInstaller(manager: manager)
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in false }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }), writingInstaller: installer)
        let view = RebuildWritingView(session: session, isModelCached: { _ in false })
        try view.inspect().find(button: "Install correction model").tap()
        try await waitFor { pending != nil }
        XCTAssertNil(try view.inspect().find(ViewType.ProgressView.self).fractionCompleted())
        let repo = AppDefaults.semanticCorrectionModelRepo
        manager.downloadFraction[repo] = 0.42
        manager.downloadProgress[repo] = "Fixture download progress"
        XCTAssertEqual(try view.inspect().find(ViewType.ProgressView.self).fractionCompleted(), 0.42)
        _ = try view.inspect().find(text: "Fixture download progress")
        try view.inspect().find(button: "Cancel install").tap()
        try await waitFor { installer.cancelling }
        XCTAssertTrue(try view.inspect().find(button: "Cancelling…").isDisabled())
        try XCTUnwrap(pending).resume(returning: URL(fileURLWithPath: "/unused-fixture-python"))
        try await waitFor { !installer.isRunning }
        XCTAssertFalse(session.maintenanceInProgress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        _ = try view.inspect().find(button: "Install correction model")
    }
}
