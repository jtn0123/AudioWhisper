import AppKit
import AVFoundation

struct RebuildModelSelection: Equatable {
    let provider: TranscriptionProvider
    let whisper: WhisperModel
    let parakeet: ParakeetModel

    static var current: Self {
        Self(
            provider: AppDefaults.transcriptionProvider,
            whisper: AppDefaults.selectedWhisperModel, parakeet: AppDefaults.selectedParakeetModel)
    }

    var key: String {
        provider.rawValue + ":" + (provider == .local ? whisper.rawValue : parakeet.rawValue)
    }
}

/// The first-use coordinator can be tested without requesting OS consent,
/// installing real models, or probing the developer's runtime.
@MainActor
struct RebuildSetupServices {
    var selection: () -> RebuildModelSelection
    var microphoneStatus: () -> AVAuthorizationStatus
    var requestMicrophone: (@escaping @Sendable (Bool) -> Void) -> Void
    var openMicrophoneSettings: () -> Void
    var runtimeReady: (RebuildModelSelection) async -> Bool
    var modelInstalled: (RebuildModelSelection) async -> Bool
    var install: (RebuildModelSelection) async throws -> Void

    static var live: Self {
        Self(
            selection: { .current },
            microphoneStatus: { AVCaptureDevice.authorizationStatus(for: .audio) },
            requestMicrophone: { AVCaptureDevice.requestAccess(for: .audio, completionHandler: $0) },
            openMicrophoneSettings: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            },
            runtimeReady: { selection in selection.provider == .local ? true : await UvBootstrap.isEnvReady() },
            modelInstalled: { selection in
                selection.provider == .local
                    ? WhisperKitStorage.isModelDownloaded(selection.whisper)
                    : await ParakeetService.shared.isModelCached(model: selection.parakeet)
            },
            install: installSelectedModel
        )
    }

    private static func installSelectedModel(_ selection: RebuildModelSelection) async throws {
        if selection.provider == .local {
            try await ModelManager.shared.downloadModel(selection.whisper)
            return
        }
        guard Arch.isAppleSilicon else {
            throw NSError(
                domain: "AudioWhisper", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Parakeet needs Apple Silicon. Choose Whisper on this Mac."])
        }
        _ = try await UvBootstrap.ensureVenv(forceRefresh: true)
        await MLXModelManager.shared.downloadParakeetModel(repo: selection.parakeet.rawValue)
        guard await ParakeetService.shared.isModelCached(model: selection.parakeet) else {
            throw NSError(
                domain: "AudioWhisper", code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    MLXModelManager.shared.downloadProgress[selection.parakeet.rawValue]
                    ?? "The download did not finish. Check your connection and retry."])
        }
    }
}
