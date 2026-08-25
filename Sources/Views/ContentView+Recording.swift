import AppKit

/// Thin delegations to `RecordingViewModel`.
///
/// Audit item A1: the bodies of these methods used to live here — permission
/// checks, recorder lifecycle, cancellation, `AVAsset` duration loading,
/// pipeline construction and error mapping, ~290 lines in an extension on a
/// SwiftUI `View`. A `View` struct is re-created on every render and cannot be
/// instantiated in a test without a rendering context, so this file measured
/// 0.0% coverage and the app's primary flow had none. Worse, the logic was
/// duplicated: `RecordingViewModel.startRecording(...)` and
/// `TranscriptionCoordinator.runTranscription(...)` already existed and were
/// tested, but had zero production callers.
///
/// The logic now lives in `RecordingViewModel+Transcription.swift`. What stays
/// here is only what genuinely belongs to the view: reading its `@AppDefault`
/// hint flag and routing dashboard presentation through its `windowCoordinator`
/// so redirect reasons keep surfacing in `WindowCoordinator` logs.
internal extension ContentView {

    func startRecording() {
        viewModel.startRecording(
            audioRecorder: audioRecorder,
            permissionManager: permissionManager
        )
    }

    func stopAndProcess() {
        viewModel.stopAndProcess(
            audioRecorder: audioRecorder,
            hasShownFirstModelUseHint: hasShownFirstModelUseHint,
            setHintShown: { hasShownFirstModelUseHint = true },
            presentDashboard: { reason in
                windowCoordinator.presentDashboard(reason: reason)
            }
        )
    }

    func transcribeExternalAudioFile(_ audioURL: URL) {
        viewModel.transcribeExternalAudioFile(
            audioURL,
            hasShownFirstModelUseHint: hasShownFirstModelUseHint,
            setHintShown: { hasShownFirstModelUseHint = true },
            presentDashboard: { reason in
                windowCoordinator.presentDashboard(reason: reason)
            }
        )
    }

    func retryLastTranscription() {
        viewModel.retryLastTranscription()
    }

    /// Stays in the view: `NSWorkspace` file reveal is presentation, and it
    /// needs no transcription state beyond `lastAudioURL`.
    func showLastAudioFile() {
        guard let audioURL = viewModel.lastAudioURL else {
            viewModel.errorMessage = LocalizedStrings.Errors.noAudioFileToShow
            viewModel.showError = true
            return
        }

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            viewModel.errorMessage = LocalizedStrings.Errors.audioFileMissing
            viewModel.showError = true
            viewModel.lastAudioURL = nil
            return
        }

        NSWorkspace.shared.selectFile(
            audioURL.path,
            inFileViewerRootedAtPath: audioURL.deletingLastPathComponent().path
        )
    }
}
