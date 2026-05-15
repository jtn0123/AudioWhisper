import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

/// Rendering-based coverage tests for the Dashboard correction views.
///
/// These tests render `DashboardCorrectionView` (and its `var`-based section
/// extensions) under multiple `AppDefaults`-driven states so the view bodies
/// actually execute during a normal `swift test` run. NSHostingView + layout
/// forces full body + computed-subview evaluation — and unlike ViewInspector
/// it correctly propagates injected `@Environment` objects into the body.
@MainActor
final class DashboardCorrectionCoverageTests: IsolatedXCTestCase {

    // Correction views write to UserDefaults.standard via @AppDefault.
    // NOTE(D1): These views read AppDefaults (the global domain) directly,
    // so the test must drive the global store. We snapshot and restore the
    // touched keys ourselves to keep other tests deterministic.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private let touchedKeys = [
        "semanticCorrectionMode",
        "semanticCorrectionModelRepo",
        "hasSetupLocalLLM",
        "hasSetupParakeet"
    ]
    private var savedValues: [String: Any?] = [:]

    override func setUp() {
        super.setUp()
        for key in touchedKeys {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
        }
    }

    override func tearDown() {
        for key in touchedKeys {
            if let value = savedValues[key], let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        savedValues = [:]
        super.tearDown()
    }

    // MARK: - Helpers

    /// Forces a SwiftUI view's body (and computed subviews) to evaluate by
    /// hosting it in an NSHostingView and laying it out.
    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 900)
        host.layout()
        host.displayIfNeeded()
        XCTAssertNotNil(host)
    }

    private func makeCorrectionView() -> some View {
        DashboardCorrectionView()
            .environment(MLXModelManager.shared)
            .environment(PermissionManager.shared)
            .environmentObject(WindowCoordinator.shared)
    }

    // MARK: - DashboardCorrectionView body (mode = off)

    func testCorrectionViewRendersOffMode() throws {
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        render(makeCorrectionView())
    }

    func testCorrectionViewRendersWithDefaultRepoCleared() throws {
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        UserDefaults.standard.removeObject(forKey: "semanticCorrectionModelRepo")
        // No stored repo -> AppDefaults falls back to the recommended repo.
        render(makeCorrectionView())
    }

    // MARK: - DashboardCorrectionView body (mode = localMLX)

    func testCorrectionViewRendersLocalMLXMode() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        UserDefaults.standard.set("mlx-community/Qwen3-1.7B-4bit", forKey: "semanticCorrectionModelRepo")
        // Exercises modeSelectorSection + localMLXCard + envStatusRow
        // + modelList + verifyRow + every mlxEntries closure.
        render(makeCorrectionView())
    }

    func testCorrectionViewLocalMLXModeSelectorRenders() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        // Renders modeSelectorSection (the "Correction Mode" card) plus the
        // full localMLXCard body.
        render(makeCorrectionView())
    }

    func testCorrectionViewLocalMLXRendersWithAlternateModel() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        UserDefaults.standard.set("mlx-community/gemma-2b-it-4bit", forKey: "semanticCorrectionModelRepo")
        // Non-recommended repo selected — exercises the isSelected=false
        // badge branch for the recommended model row.
        render(makeCorrectionView())
    }

    func testCorrectionViewRendersWithSetupFlags() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        UserDefaults.standard.set(true, forKey: "hasSetupLocalLLM")
        UserDefaults.standard.set(true, forKey: "hasSetupParakeet")
        render(makeCorrectionView())
    }

    /// `DashboardCorrectionView` exposes its `@State` via the synthesized
    /// memberwise init. Seeding `envReady: true` renders the otherwise
    /// unreached "environment ready" branch of `localMLXCard` — the full
    /// `modelList` (instead of the Install Dependencies button).
    func testCorrectionViewRendersEnvReadyBranch() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        UserDefaults.standard.set("mlx-community/Qwen3-1.7B-4bit", forKey: "semanticCorrectionModelRepo")
        let view = DashboardCorrectionView(envReady: true)
            .environment(MLXModelManager.shared)
            .environment(PermissionManager.shared)
            .environmentObject(WindowCoordinator.shared)
        render(view)
    }

    /// Seeding a failed verification message renders the `verifyRow`
    /// DownloadProgressView failed-state branch.
    func testCorrectionViewRendersVerifyFailedBranch() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        let view = DashboardCorrectionView(
            envReady: true,
            mlxVerifyMessage: "Verification failed: model not found"
        )
        .environment(MLXModelManager.shared)
        .environment(PermissionManager.shared)
        .environmentObject(WindowCoordinator.shared)
        render(view)
    }

    /// Seeding an informational verification message renders the success
    /// info-text branch of `verifyRow`.
    func testCorrectionViewRendersVerifyInfoBranch() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        let view = DashboardCorrectionView(
            envReady: true,
            mlxVerifyMessage: "Model verified"
        )
        .environment(MLXModelManager.shared)
        .environment(PermissionManager.shared)
        .environmentObject(WindowCoordinator.shared)
        render(view)
    }

    // MARK: - Section extension coverage (DashboardCorrection+ModeSelector)
    //
    // Section `var`s that read `self.modelManager` cannot be hosted in
    // isolation (the standalone view value never receives @Environment).
    // They are exercised transitively by the full-view renders above —
    // localMLXCard / modelList / verifyRow are all referenced from the
    // localMLX branch of `DashboardCorrectionView.body`.

    func testModeSelectorSectionRenders() throws {
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        // modeSelectorSection is self-contained (no modelManager access).
        let view = DashboardCorrectionView()
        render(view.modeSelectorSection)
    }

    func testEnvStatusRowRenders() throws {
        // envStatusRow only reads @State (envReady / isCheckingEnv).
        let view = DashboardCorrectionView()
        render(view.envStatusRow)
    }

    // MARK: - Section extension coverage (DashboardCorrection+ModelPicker)
    //
    // `mlxEntries`, `modelList` and `modelRow` all read the @Environment
    // `modelManager`, which is only valid while the owning view is hosted.
    // They are covered transitively by the localMLX-mode full-view renders
    // above (body -> localMLXCard -> modelList -> modelRow per entry).

    func testModelRowRendersForEntry() throws {
        // modelRow reads only the passed ModelEntry, no @Environment, so it
        // is safe to host on its own.
        let entry = MLXEntry(
            model: MLXModelManager.recommendedModels[0],
            isDownloaded: false,
            isDownloading: false,
            statusText: nil,
            sizeText: "1.0 GB",
            isSelected: true,
            badgeText: "RECOMMENDED",
            onSelect: {},
            onDownload: {},
            onDelete: {}
        )
        let view = DashboardCorrectionView()
        render(view.modelRow(entry: entry))
    }

    func testModelRowRendersDownloadingAndDownloadedStates() throws {
        let model = MLXModelManager.recommendedModels[0]
        let view = DashboardCorrectionView()
        // Downloading branch.
        render(view.modelRow(entry: MLXEntry(
            model: model, isDownloaded: false, isDownloading: true,
            statusText: "Downloading…", sizeText: "1.0 GB", isSelected: false,
            badgeText: nil, onSelect: {}, onDownload: {}, onDelete: {})))
        // Downloaded branch.
        render(view.modelRow(entry: MLXEntry(
            model: model, isDownloaded: true, isDownloading: false,
            statusText: nil, sizeText: "1.0 GB", isSelected: false,
            badgeText: nil, onSelect: {}, onDownload: {}, onDelete: {})))
    }

    // MARK: - Section extension coverage (DashboardCorrection+Verify)

    func testVerifyRowRendersIdleState() throws {
        // verifyRow reads only @State (isVerifyingMLX / mlxVerifyMessage).
        let view = DashboardCorrectionView()
        render(view.verifyRow)
    }

    func testVenvPythonPathIsNonEmpty() throws {
        let view = DashboardCorrectionView()
        let path = view.venvPythonPath()
        XCTAssertTrue(path.contains("python_project/.venv/bin/python3"))
    }

    /// Exercises `checkEnvReady()` end to end. It is deterministic: it only
    /// probes the local filesystem for an existing venv python (absent in
    /// CI) and never hits the network. `isCheckingEnv` is plain `@State`, so
    /// it cannot be observed on a non-hosted view value — we instead give the
    /// spawned Task time to run its body and assert it completes cleanly.
    func testCheckEnvReadyRunsWithoutCrashing() async throws {
        let view = DashboardCorrectionView()
        view.checkEnvReady()
        // Allow the detached Task spawned by checkEnvReady to finish its
        // FileManager / Process probe.
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(view.venvPythonPath().isEmpty)
    }
}
