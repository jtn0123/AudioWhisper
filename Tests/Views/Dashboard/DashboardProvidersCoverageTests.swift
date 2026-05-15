import XCTest
import SwiftUI
import AppKit
@testable import AudioWhisper

/// Rendering-based coverage tests for the Dashboard providers views.
///
/// `DashboardProvidersView` is composed of many `var`-based section
/// extensions (engine selector, local whisper, parakeet, correction). These
/// tests render the parent view under multiple `AppDefaults`-driven states so
/// every conditional branch in the section bodies is executed during a
/// normal `swift test` run. NSHostingView + layout forces body evaluation
/// while correctly propagating injected `@Environment` objects.
@MainActor
final class DashboardProvidersCoverageTests: IsolatedXCTestCase {

    // NOTE(D1): DashboardProvidersView reads AppDefaults (the global domain)
    // directly via @AppDefault, so the test must drive UserDefaults.standard.
    // We snapshot and restore the touched keys to keep other tests stable.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private let touchedKeys = [
        "transcriptionProvider",
        "selectedWhisperModel",
        "selectedParakeetModel",
        "hasSetupParakeet",
        "hasSetupLocalLLM",
        "maxModelStorageGB",
        "semanticCorrectionMode",
        "semanticCorrectionModelRepo"
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

    private func render<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 1200)
        host.layout()
        host.displayIfNeeded()
        XCTAssertNotNil(host)
    }

    private func makeProvidersView() -> some View {
        DashboardProvidersView()
            .environment(MLXModelManager.shared)
            .environment(PermissionManager.shared)
            .environmentObject(WindowCoordinator.shared)
    }

    // MARK: - DashboardProvidersView body (provider = local)

    func testProvidersViewRendersLocalProvider() throws {
        UserDefaults.standard.set("local", forKey: "transcriptionProvider")
        UserDefaults.standard.set("base", forKey: "selectedWhisperModel")
        UserDefaults.standard.set(5.0, forKey: "maxModelStorageGB")
        // Exercises headerSection + engineSection + localWhisperCard
        // + correctionSection (mode off).
        render(makeProvidersView())
    }

    func testProvidersViewRendersLocalWithDefaultsCleared() throws {
        UserDefaults.standard.set("local", forKey: "transcriptionProvider")
        UserDefaults.standard.removeObject(forKey: "maxModelStorageGB")
        UserDefaults.standard.removeObject(forKey: "selectedWhisperModel")
        // Cleared defaults -> AppDefaults fallback values are exercised.
        render(makeProvidersView())
    }

    // MARK: - DashboardProvidersView body (provider = parakeet)

    func testProvidersViewRendersParakeetProvider() throws {
        UserDefaults.standard.set("parakeet", forKey: "transcriptionProvider")
        UserDefaults.standard.set("mlx-community/parakeet-tdt-0.6b-v3", forKey: "selectedParakeetModel")
        // Exercises parakeetCard + environmentStatusSection + modelSelectionSection.
        render(makeProvidersView())
    }

    func testProvidersViewParakeetWithSetupFlag() throws {
        UserDefaults.standard.set("parakeet", forKey: "transcriptionProvider")
        UserDefaults.standard.set(true, forKey: "hasSetupParakeet")
        UserDefaults.standard.set(true, forKey: "hasSetupLocalLLM")
        render(makeProvidersView())
    }

    // MARK: - DashboardProvidersView body (correction = localMLX)

    func testProvidersViewRendersCorrectionLocalMLX() throws {
        UserDefaults.standard.set("local", forKey: "transcriptionProvider")
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        UserDefaults.standard.set("mlx-community/Qwen3-1.7B-4bit", forKey: "semanticCorrectionModelRepo")
        // correctionSection shows correctionMLXSection when mode == localMLX,
        // iterating correctionModelRow for each recommended model.
        render(makeProvidersView())
    }

    func testProvidersViewCorrectionOffMode() throws {
        UserDefaults.standard.set("local", forKey: "transcriptionProvider")
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        render(makeProvidersView())
    }

    // MARK: - engineSection / engineCard (DashboardProviders+EngineSelector)

    func testEngineSectionRenders() throws {
        UserDefaults.standard.set("local", forKey: "transcriptionProvider")
        render(makeProvidersView())
    }

    // The following section `var`s/`func`s read only @AppDefault and @State
    // (no @Environment), so they can be hosted standalone. Sections that read
    // the @Environment `mlxModelManager` (parakeetCard, correctionSection,
    // correctionMLXSection, correctionModelRow) cannot be hosted in isolation
    // and are covered transitively by the full-view renders above.

    func testEngineCardRendersForEachProvider() throws {
        let view = DashboardProvidersView()
        for provider in TranscriptionProvider.allCases {
            render(view.engineCard(provider))
        }
    }

    func testStatusBadgeRendersForEachProvider() throws {
        let view = DashboardProvidersView()
        for provider in TranscriptionProvider.allCases {
            render(view.statusBadge(for: provider))
        }
    }

    func testHeaderSectionRenders() throws {
        let view = DashboardProvidersView()
        render(view.headerSection)
    }

    func testEngineConfigCoversAllProviders() throws {
        let view = DashboardProvidersView()
        for provider in TranscriptionProvider.allCases {
            let config = view.engineConfig(for: provider)
            XCTAssertFalse(config.icon.isEmpty)
            XCTAssertFalse(config.tagline.isEmpty)
        }
    }

    func testStatusInfoCoversAllProviders() throws {
        let view = DashboardProvidersView()
        let (localText, _) = view.statusInfo(for: .local)
        XCTAssertFalse(localText.isEmpty)
        let (parakeetText, _) = view.statusInfo(for: .parakeet)
        XCTAssertFalse(parakeetText.isEmpty)
    }

    // MARK: - localWhisperCard (DashboardProviders+LocalWhisper)
    //
    // localWhisperCard reads only the @State `ModelManager` (initialised to
    // `.shared`) and @AppDefault values — no @Environment — so it hosts
    // standalone. parakeetCard and the correction sections read the
    // @Environment `mlxModelManager` and are covered by the full-view
    // renders instead.

    func testLocalWhisperCardRenders() throws {
        UserDefaults.standard.set("base", forKey: "selectedWhisperModel")
        UserDefaults.standard.set(5.0, forKey: "maxModelStorageGB")
        let view = DashboardProvidersView()
        render(view.localWhisperCard)
    }

    func testLocalWhisperCardRendersWithAlternateModelAndStorage() throws {
        UserDefaults.standard.set("tiny", forKey: "selectedWhisperModel")
        UserDefaults.standard.set(10.0, forKey: "maxModelStorageGB")
        let view = DashboardProvidersView()
        // Non-base model selected — exercises the non-recommended-badge branch.
        render(view.localWhisperCard)
    }

    // MARK: - correctionModeSection (DashboardProviders+Correction)

    func testCorrectionModeSectionRenders() throws {
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        let view = DashboardProvidersView()
        // correctionModeSection reads only the @AppDefault correction mode.
        render(view.correctionModeSection)
    }

    func testCorrectionModeSectionRendersLocalMLX() throws {
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        let view = DashboardProvidersView()
        render(view.correctionModeSection)
    }

    // MARK: - envReady = true rendering paths

    /// `DashboardProvidersView` stores env state in an @Observable
    /// `ProviderSettingsState` behind `@State`. Pre-seeding `envReady = true`
    /// on the view value before hosting renders the otherwise-unreached
    /// "ready" branches: the parakeet Verify button + the MLX correction
    /// model list with cleanup affordances.
    func testProvidersViewParakeetRendersEnvReadyBranch() throws {
        UserDefaults.standard.set("parakeet", forKey: "transcriptionProvider")
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        let view = DashboardProvidersView()
        view.envReady = true
        render(
            view
                .environment(MLXModelManager.shared)
                .environment(PermissionManager.shared)
                .environmentObject(WindowCoordinator.shared)
        )
    }

    func testProvidersViewLocalRendersEnvReadyCorrectionBranch() throws {
        UserDefaults.standard.set("local", forKey: "transcriptionProvider")
        UserDefaults.standard.set("localMLX", forKey: "semanticCorrectionMode")
        UserDefaults.standard.set("mlx-community/Qwen3-1.7B-4bit", forKey: "semanticCorrectionModelRepo")
        let view = DashboardProvidersView()
        view.envReady = true
        render(
            view
                .environment(MLXModelManager.shared)
                .environment(PermissionManager.shared)
                .environmentObject(WindowCoordinator.shared)
        )
    }

    func testProvidersViewParakeetRendersVerifyMessageBranches() throws {
        UserDefaults.standard.set("parakeet", forKey: "transcriptionProvider")
        let view = DashboardProvidersView()
        view.envReady = true
        // A failure message routes parakeetCard through the DownloadProgressView
        // failed-state branch.
        view.parakeetVerifyMessage = "Verification failed: model missing"
        render(
            view
                .environment(MLXModelManager.shared)
                .environment(PermissionManager.shared)
                .environmentObject(WindowCoordinator.shared)
        )
    }

    func testProvidersViewParakeetRendersInfoMessageBranch() throws {
        UserDefaults.standard.set("parakeet", forKey: "transcriptionProvider")
        let view = DashboardProvidersView()
        view.envReady = true
        // An informational (non-failure) message routes through the info row.
        view.parakeetVerifyMessage = "Model verified"
        render(
            view
                .environment(MLXModelManager.shared)
                .environment(PermissionManager.shared)
                .environmentObject(WindowCoordinator.shared)
        )
    }

    func testProvidersViewLocalRendersDownloadErrorBranch() throws {
        UserDefaults.standard.set("local", forKey: "transcriptionProvider")
        let view = DashboardProvidersView()
        // A download error routes localWhisperCard through its failed-state
        // DownloadProgressView branch.
        view.downloadError = "Network unreachable"
        render(
            view
                .environment(MLXModelManager.shared)
                .environment(PermissionManager.shared)
                .environmentObject(WindowCoordinator.shared)
        )
    }

    // MARK: - Environment check (DashboardProviders+Parakeet)

    /// Exercises `checkEnvReady()`. Deterministic: it only probes the local
    /// filesystem for an existing venv python and never hits the network.
    /// `isCheckingEnv` is backed by the @Observable ProviderSettingsState so
    /// it is observable on a non-hosted view value; we poll until the
    /// spawned Task flips it back to false.
    func testCheckEnvReadyCompletes() async throws {
        let view = DashboardProvidersView()
        view.checkEnvReady()
        for _ in 0..<200 where view.isCheckingEnv {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(view.isCheckingEnv, "checkEnvReady should finish")
    }

    // MARK: - MLXModelManagementView

    func testMLXModelManagementViewRenders() throws {
        var repo = "mlx-community/Llama-3.2-1B-Instruct-4bit"
        let binding = Binding(get: { repo }, set: { repo = $0 })
        render(
            MLXModelManagementView(selectedModelRepo: binding)
                .environment(MLXModelManager.shared)
        )
    }

    func testMLXModelManagementViewRendersWithQwenRepo() throws {
        var repo = "mlx-community/Qwen3-1.7B-4bit"
        let binding = Binding(get: { repo }, set: { repo = $0 })
        render(
            MLXModelManagementView(selectedModelRepo: binding)
                .environment(MLXModelManager.shared)
        )
    }

    func testMLXModelManagementViewRendersWithRecommendedRepo() throws {
        // Selecting the repo flagged as recommended exercises the badge branch.
        var repo = "mlx-community/Llama-3.2-1B-Instruct-4bit"
        let binding = Binding(get: { repo }, set: { repo = $0 })
        render(
            MLXModelManagementView(selectedModelRepo: binding)
                .environment(MLXModelManager.shared)
        )
    }
}
