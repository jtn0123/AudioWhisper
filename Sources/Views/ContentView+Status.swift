internal extension ContentView {
    func enhanceProgressMessage(_ message: String) -> String {
        return message
    }

    func updateStatus() {
        viewModel.statusViewModel.updateStatus(
            isRecording: audioRecorder.isRecording,
            isProcessing: isProcessing,
            progressMessage: viewModel.progressMessage,
            hasPermission: permissionManager.microphonePermissionState == .granted,
            showSuccess: viewModel.showSuccess,
            errorMessage: viewModel.showError ? viewModel.errorMessage : nil
        )
    }

}
