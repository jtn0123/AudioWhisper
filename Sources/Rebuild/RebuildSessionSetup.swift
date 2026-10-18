import Foundation

extension RebuildSession {
    func checkResolvedMode(_ mode: ResolvedDictationMode, id: UUID) async -> Bool {
        let selection = mode.selection
        let runtime = await setup.runtimeReady(selection)
        let installed = await setup.modelInstalled(selection)
        let assets = await setup.assetIdentity(selection)
        guard !Task.isCancelled, sessionID == id else { return false }
        let failure = verificationStore.failure(for: selection, assets: assets)
        guard runtime, installed, failure == nil, setup.microphoneStatus() == .authorized else {
            notice = failure ?? "The mode \(mode.name ?? "Custom settings") needs its voice model, runtime and microphone access. "
                + "Choose it manually in Models & setup to finish setup."
            phase = .failed
            return false
        }
        return true
    }
    func removeVoiceModel() async {
        guard !phase.isBusy, !isInstalling, !maintenanceInProgress else { return }
        maintenanceInProgress = true
        modelRemovalError = nil
        defer { maintenanceInProgress = false }
        do {
            try await setup.remove(setup.selection())
            await refreshSetup()
        } catch { modelRemovalError = error.localizedDescription }
    }

    var captureIdentity: UUID? { sessionID }
    var recordingDestinationName: String {
        AppDefaults.enableSmartPaste ? (capturedTarget?.displayName ?? "Clipboard") : "Clipboard"
    }

    func cancel() {
        livePreview.stop(clear: true)
        discardRetry()
        sessionID = nil
        job?.cancel()
        job = nil
        services.cancel()
        phase = .idle
        notice = nil
        writingContext = nil
        contextRequested = false
        closeRecorder()
    }
    var recordingActionTitle: String {
        if phase == .starting { return "Connecting microphone…" }
        if phase == .recording { return "Finish recording" }
        if phase == .transcribing { return "Transcribing…" }
        if isInstalling { return "Installing…" }
        if isVerifyingVoiceModel { return "Verifying…" }
        if maintenanceInProgress { return maintenanceLabel ?? "Updating voice model…" }
        return readiness.ready ? "Start recording" : "Finish setup"
    }

    var canToggleRecording: Bool {
        phase == .recording || (!phase.isBusy && !isInstalling && !maintenanceInProgress)
    }

    var recordingBlockedReason: String? {
        if phase == .recording { return nil }
        if let reason = fileBlockedReason { return reason }
        return readiness.microphoneGranted ? nil : "Allow microphone access in Voice Models."
    }

    var canImportAudio: Bool { fileBlockedReason == nil }

    var fileBlockedReason: String? {
        if phase == .starting { return "Wait for the microphone to connect or cancel." }
        if phase == .recording { return "Finish or cancel the recording first." }
        if phase == .transcribing { return "Wait for transcription or cancel it first." }
        if isInstalling { return "Wait for the voice model installation to finish." }
        if maintenanceInProgress { return maintenanceLabel ?? "Wait for model verification or maintenance to finish." }
        if readiness.checking { return "Wait for the setup check to finish." }
        if !readiness.runtimeReady { return "Install the local runtime in Voice Models." }
        if !readiness.modelInstalled { return "Install your voice model in Voice Models." }
        if readiness.modelVerificationFailed { return "Repair or verify your voice model in Voice Models." }
        return nil
    }

    var retryBlockedReason: String? {
        if effectiveMode?.origin == .appRule {
            return phase.isBusy || isInstalling || maintenanceInProgress ? "Finish the current job before retrying." : nil
        }
        if let reason = fileBlockedReason { return reason }
        guard let config = retryAudio?.config else { return nil }
        let selected = setup.selection()
        let sameModel = config.provider == selected.provider && (
            config.provider == .local ? config.whisperModel == selected.whisper : config.parakeetModel == selected.parakeet)
        return sameModel ? nil : "Select the voice model used for this recording before retrying."
    }

    func verifyVoiceModel() async {
        guard !phase.isBusy, !isInstalling, !maintenanceInProgress else { return }
        isVerifyingVoiceModel = true
        maintenanceInProgress = true
        verificationMessage = nil
        defer {
            isVerifyingVoiceModel = false
            maintenanceInProgress = false
        }
        let selection = setup.selection()
        let assets = await setup.assetIdentity(selection)
        guard !Task.isCancelled, selection == setup.selection() else { return }
        let result: ModelVerificationResult
        do {
            result = try await setup.verify(selection)
        } catch {
            result = ModelVerificationResult(succeeded: false, message: "Verification failed: \(error.localizedDescription)")
        }
        let currentAssets = await setup.assetIdentity(selection)
        guard !Task.isCancelled, selection == setup.selection(), assets == currentAssets else {
            await refreshSetup()
            return
        }
        verificationStore.record(result, for: selection, assets: assets)
        verificationSelection = selection
        verificationAssets = assets
        verificationMessage = result.message
        await refreshSetup()
    }

    func refreshSetup() async {
        refreshAgain = true
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        while refreshAgain {
            refreshAgain = false
            let selection = setup.selection()
            let runtime = await setup.runtimeReady(selection)
            let installed = await setup.modelInstalled(selection)
            let assets = await setup.assetIdentity(selection)
            guard selection == setup.selection() else {
                refreshAgain = true
                continue
            }
            let failure = verificationStore.failure(for: selection, assets: assets)
            if verificationSelection != selection || verificationAssets != assets { verificationMessage = nil }
            if let failure {
                verificationSelection = selection
                verificationAssets = assets
                verificationMessage = failure
            }
            readiness = RebuildReadiness(
                microphoneGranted: setup.microphoneStatus() == .authorized,
                modelInstalled: installed, runtimeReady: runtime, checking: false,
                modelVerificationFailed: failure != nil
            )
        }
    }

    func requestMicrophone() {
        guard !isRequestingMicrophone else { return }
        switch setup.microphoneStatus() {
        case .notDetermined:
            isRequestingMicrophone = true
            setup.requestMicrophone { [weak self] _ in
                Task { @MainActor in
                    self?.isRequestingMicrophone = false
                    await self?.refreshSetup()
                }
            }
        case .denied, .restricted:
            setup.openMicrophoneSettings()
        default: Task { await refreshSetup() }
        }
    }

    func installVoiceModel() async {
        guard !isInstalling, !phase.isBusy, !maintenanceInProgress else { return }
        isInstalling = true
        setupError = nil
        defer { isInstalling = false }
        let selection = setup.selection()
        do {
            try await setup.install(selection)
        } catch { setupError = error.localizedDescription }
        await refreshSetup()
    }

}
