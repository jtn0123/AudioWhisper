import Foundation
import Observation

/// Observable state container for provider-related UI state.
/// Centralizes the scattered @State variables from DashboardProvidersView
/// for better testability and maintainability.
@Observable
@MainActor
final class ProviderSettingsState {
    // MARK: - Environment State
    var envReady = false
    var isCheckingEnv = false

    // MARK: - Setup Sheet State
    var showSetupSheet = false
    var isSettingUp = false
    var setupLogs = ""
    var setupStatus: String?

    // MARK: - Parakeet State
    var parakeetVerifyMessage: String?
    var isVerifyingParakeet = false

    // MARK: - Model Download State
    var downloadError: String?
    var failedDownloadModel: WhisperModel?
    var totalModelsSize: Int64 = 0
    var downloadedModels: [WhisperModel] = []
    var modelDownloadStates: [WhisperModel: Bool] = [:]
    var downloadStartTime: [WhisperModel: Date] = [:]

    // MARK: - MLX Correction State
    var isRefreshingMLXModels = false
    var isVerifyingMLX = false
    var mlxVerifyMessage: String?

    // MARK: - Animation State
    var isLoaded = false

    // MARK: - Initialization

    init() {}

    // MARK: - Status Helpers

    func statusInfo(
        for provider: TranscriptionProvider,
        selectedWhisperModel: WhisperModel = AppDefaults.selectedWhisperModel,
        parakeetModelCached: Bool = false
    ) -> (text: String, isReady: Bool) {
        let requirement = RecordingSetupRequirement.modelRequirement(RecordingSetupInputs(
            provider: provider,
            whisperModel: selectedWhisperModel,
            downloadedWhisperModels: Set(downloadedModels),
            parakeetModel: AppDefaults.selectedParakeetModel,
            environmentReady: envReady,
            parakeetModelCached: parakeetModelCached,
            supportsParakeet: RecordingSetupState.supportsParakeet
        ))
        return (requirement.isReady ? "Installed" : "Setup", requirement.isReady)
    }

    func beginDownload(_ model: WhisperModel) {
        downloadError = nil
        failedDownloadModel = nil
        downloadStartTime[model] = Date()
    }

    func finishDownload(_ model: WhisperModel, error: String? = nil) {
        downloadStartTime.removeValue(forKey: model)
        if let error {
            downloadError = error
            failedDownloadModel = model
        }
    }

    func retryFailedDownload(using download: (WhisperModel) -> Void) {
        guard let model = failedDownloadModel else { return }
        download(model)
    }

    // MARK: - Environment Check

    func checkEnvReady() {
        isCheckingEnv = true
        Task {
            let ready = await UvBootstrap.isEnvReady()
            await MainActor.run {
                self.envReady = ready
                self.isCheckingEnv = false
            }
        }
    }

    // MARK: - Model State Management

    func loadModelStates(from modelManager: ModelManager) {
        downloadedModels = Array(modelManager.downloadedModels)
        for model in WhisperModel.allCases {
            modelDownloadStates[model] = downloadedModels.contains(model)
        }
    }

    // MARK: - Setup Operations

    func beginSetup(title: String) {
        setupStatus = title
        setupLogs = ""
        isSettingUp = true
        showSetupSheet = true
    }

    func completeSetup(success: Bool, message: String) {
        isSettingUp = false
        setupStatus = message
        if success {
            envReady = true
        }
    }

    func appendSetupLog(_ message: String) {
        setupLogs += (setupLogs.isEmpty ? "" : "\n") + message
    }

    func dismissSetupSheet() {
        showSetupSheet = false
    }

    // MARK: - Reset

    func reset() {
        envReady = false
        isCheckingEnv = false
        showSetupSheet = false
        isSettingUp = false
        setupLogs = ""
        setupStatus = nil
        parakeetVerifyMessage = nil
        isVerifyingParakeet = false
        downloadError = nil
        failedDownloadModel = nil
        totalModelsSize = 0
        downloadedModels = []
        modelDownloadStates = [:]
        downloadStartTime = [:]
        isRefreshingMLXModels = false
        isVerifyingMLX = false
        mlxVerifyMessage = nil
        isLoaded = false
    }
}
