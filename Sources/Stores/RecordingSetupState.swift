import Foundation
import Observation

internal struct RecordingSetupInputs {
    var provider: TranscriptionProvider
    var whisperModel: WhisperModel
    var downloadedWhisperModels: Set<WhisperModel>
    var parakeetModel: ParakeetModel
    var environmentReady: Bool?
    var parakeetModelCached: Bool
    var supportsParakeet: Bool
}

internal enum RecordingSetupRequirement: Equatable {
    case ready
    case microphone
    case microphoneRequesting
    case microphoneDenied
    case microphoneRestricted
    case checking
    case whisperModel(WhisperModel)
    case parakeetEnvironment
    case parakeetModel(ParakeetModel)
    case unsupportedHardware

    var isReady: Bool { self == .ready }

    var message: String {
        switch self {
        case .ready: return "Ready to record"
        case .microphone: return "Allow microphone access"
        case .microphoneRequesting: return "Waiting for microphone access"
        case .microphoneDenied: return "Enable microphone access in System Settings"
        case .microphoneRestricted: return "Microphone access is restricted on this Mac"
        case .checking: return "Checking recording setup"
        case .whisperModel(let model): return "Download \(model.displayName) to record"
        case .parakeetEnvironment: return "Install the Parakeet environment"
        case .parakeetModel(let model): return "Download Parakeet \(model.displayName) to record"
        case .unsupportedHardware: return "Choose Local Whisper on this Mac"
        }
    }

    static func assess(
        microphone: PermissionState,
        modelRequirement: RecordingSetupRequirement
    ) -> RecordingSetupRequirement {
        switch microphone {
        case .granted: return modelRequirement
        case .requesting: return .microphoneRequesting
        case .denied: return .microphoneDenied
        case .restricted: return .microphoneRestricted
        case .unknown, .notRequested: return .microphone
        }
    }

    static func modelRequirement(_ input: RecordingSetupInputs) -> RecordingSetupRequirement {
        switch input.provider {
        case .local:
            return input.downloadedWhisperModels.contains(input.whisperModel) ? .ready : .whisperModel(input.whisperModel)
        case .parakeet:
            guard input.supportsParakeet else { return .unsupportedHardware }
            guard let environmentReady = input.environmentReady else { return .checking }
            guard environmentReady else { return .parakeetEnvironment }
            return input.parakeetModelCached ? .ready : .parakeetModel(input.parakeetModel)
        }
    }
}

/// Shared by the menu, recording entry points, and setup checklist. Checking
/// setup never downloads a model or requests a system permission.
@MainActor
@Observable
internal final class RecordingSetupState {
    static let shared = RecordingSetupState()

    private(set) var environmentReady: Bool?
    private(set) var cachedParakeetModel: ParakeetModel?
    private(set) var isRefreshing = false
    var navigationRequest = 0
    private var refreshRequested = false
    private(set) var isInstalling = false
    private(set) var installError: String?
    @ObservationIgnored private let environmentCheck: () async -> Bool
    @ObservationIgnored private let cacheCheck: (ParakeetModel) async -> Bool

    init(
        environmentCheck: @escaping () async -> Bool = { await UvBootstrap.isEnvReady() },
        cacheCheck: @escaping (ParakeetModel) async -> Bool = { await ParakeetService.shared.isModelCached(model: $0) }
    ) {
        self.environmentCheck = environmentCheck
        self.cacheCheck = cacheCheck
    }

    static var supportsParakeet: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    var modelRequirement: RecordingSetupRequirement {
        RecordingSetupRequirement.modelRequirement(RecordingSetupInputs(
            provider: AppDefaults.transcriptionProvider,
            whisperModel: AppDefaults.selectedWhisperModel,
            downloadedWhisperModels: ModelManager.shared.downloadedModels,
            parakeetModel: AppDefaults.selectedParakeetModel,
            environmentReady: environmentReady,
            parakeetModelCached: cachedParakeetModel == AppDefaults.selectedParakeetModel,
            supportsParakeet: Self.supportsParakeet
        ))
    }

    var requirement: RecordingSetupRequirement {
        RecordingSetupRequirement.assess(
            microphone: PermissionManager.shared.microphonePermissionState,
            modelRequirement: modelRequirement
        )
    }

    func refresh() async {
        refreshRequested = true
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        while refreshRequested {
            refreshRequested = false
            PermissionManager.shared.checkPermissionState()
            await ModelManager.shared.refreshModelStates()
            let model = AppDefaults.selectedParakeetModel
            let ready = await environmentCheck()
            let cached = await cacheCheck(model)
            guard model == AppDefaults.selectedParakeetModel else {
                refreshRequested = true
                continue
            }
            environmentReady = ready
            cachedParakeetModel = cached ? model : nil
        }
    }

    func installSelectedModel() async {
        guard !isInstalling else { return }
        isInstalling = true
        installError = nil
        defer { isInstalling = false }
        let provider = AppDefaults.transcriptionProvider
        let whisper = AppDefaults.selectedWhisperModel
        let parakeet = AppDefaults.selectedParakeetModel
        do {
            if provider == .local {
                try await ModelManager.shared.downloadModel(whisper)
            } else {
                _ = try await UvBootstrap.ensureVenv(userPython: nil) { _ in }
                await MLXModelManager.shared.downloadParakeetModel(repo: parakeet.rawValue)
                if !(await cacheCheck(parakeet)) {
                    installError = MLXModelManager.shared.downloadProgress[parakeet.rawValue]
                        ?? "The voice model could not be installed. Check your connection and try again."
                }
            }
        } catch {
            installError = error.localizedDescription
        }
        await refresh()
    }

}
