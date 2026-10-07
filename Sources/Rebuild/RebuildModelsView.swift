import SwiftUI

struct RebuildSetupStatus {
    let text: String
    let tone: RebuildTone
    let busy: Bool
}

struct RebuildModelsView: View {
    @Bindable var session: RebuildSession
    @AppDefault(\.transcriptionProvider) private var provider
    @AppDefault(\.selectedWhisperModel) private var whisper
    @AppDefault(\.selectedParakeetModel) private var parakeet
    @State private var verification: String?
    private var verifying: Bool { session.isVerifyingVoiceModel }
    @State private var deletionRequested = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                microphoneStep
                voiceModelStep
                readinessRow
                storageNote
            }
            .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 860, alignment: .leading)
        }
        .task { await session.refreshSetup() }
        .onChange(of: provider) { _, _ in
            session.selectionChanged()
            verification = nil
        }
        .onChange(of: whisper) { _, _ in
            session.selectionChanged()
            verification = nil
        }
        .onChange(of: parakeet) { _, _ in
            session.selectionChanged()
            verification = nil
        }
        .confirmationDialog("Remove this voice model? You can download it again.", isPresented: $deletionRequested) {
            Button("Remove model", role: .destructive) {
                Task {
                    guard !session.phase.isBusy, !session.maintenanceInProgress else { return }
                    session.maintenanceInProgress = true
                    defer { session.maintenanceInProgress = false }
                    do {
                        if provider == .local {
                            try await ModelManager.shared.deleteModel(whisper)
                        } else {
                            await MLXModelManager.shared.deleteModel(parakeet.rawValue)
                        }
                        await session.refreshSetup()
                    } catch { verification = error.localizedDescription }
                }
            }
        }
    }

    // MARK: Step 1

    private var microphoneStep: some View {
        let granted = session.readiness.microphoneGranted
        return VStack(alignment: .leading, spacing: 10) {
            RebuildStepHeader(number: 1, title: "Microphone access", done: granted)
            HStack(spacing: 10) {
                RebuildStatusLabel(
                    text: granted ? "Microphone allowed" : "Microphone access needed",
                    tone: granted ? .success : .warning, busy: session.isRequestingMicrophone)
                Spacer()
                if !granted {
                    Button(
                        session.isRequestingMicrophone ? "Waiting for macOS…" : "Allow microphone",
                        action: session.requestMicrophone
                    )
                    .disabled(session.isRequestingMicrophone).buttonStyle(.borderedProminent)
                }
            }
            Text("Requested only when you click Allow. The recording shortcut never opens a permission dialog.")
                .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
        }.rebuildCard()
    }

    // MARK: Step 2

    private var voiceModelStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            RebuildStepHeader(number: 2, title: "Voice model", done: modelReady)
            RebuildFormRow(label: "Engine") {
                Picker("Engine", selection: $provider) {
                    Text("Parakeet · Apple Silicon").tag(TranscriptionProvider.parakeet)
                        .disabled(!Arch.isAppleSilicon)
                    Text("Whisper · any Mac").tag(TranscriptionProvider.local)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(modelActionsBlocked)
                if !Arch.isAppleSilicon {
                    Text("Parakeet requires Apple Silicon.").font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                }
            }
            RebuildFormRow(label: "Model") {
                modelPicker.disabled(modelActionsBlocked)
                Text(modelDescription).font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            installRow
            installMessages
        }.rebuildCard()
    }

    @ViewBuilder private var modelPicker: some View {
        if provider == .local {
            Picker("Whisper model", selection: $whisper) {
                ForEach(WhisperModel.allCases, id: \.self) {
                    Text(RebuildRecordView.shortName($0.displayName)).tag($0)
                }
            }
            .pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
        } else {
            Picker("Parakeet model", selection: $parakeet) {
                Text("v2 English · recommended").tag(ParakeetModel.v2English)
                Text("v3 · 25 languages").tag(ParakeetModel.v3Multilingual)
                if parakeet == .tdtCtc110mEnglish {
                    Text(RebuildRecordView.shortName(ParakeetModel.tdtCtc110mEnglish.displayName))
                        .tag(ParakeetModel.tdtCtc110mEnglish)
                }
            }
            .pickerStyle(.radioGroup).horizontalRadioGroupLayout().labelsHidden()
        }
    }

    private var modelDescription: String {
        if provider == .local {
            return "\(whisper.description) · \(whisper.fileSize). Runs through Core ML; "
                + "larger models use more memory and disk space."
        }
        return "\(parakeet.description). Runs locally on Apple Silicon; "
            + "the first install also prepares its Python runtime."
    }

    private var installRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                RebuildStatusLabel(
                    text: installStatus.text, tone: installStatus.tone,
                    busy: session.isInstalling || verifying || session.readiness.checking)
                Spacer()
                if !session.isInstalling { installButton }
            }
            if session.readiness.modelInstalled && !session.isInstalling {
                HStack(spacing: 8) {
                    Button(verifying ? "Verifying…" : "Verify model") {
                        Task { await session.verifyVoiceModel() }
                    }
                    .disabled(session.maintenanceInProgress || session.isInstalling || session.phase.isBusy)
                    .help("Load the model and transcribe a short sample to confirm it works")
                    Button("Remove selected model…", role: .destructive) { deletionRequested = true }
                        .disabled(modelActionsBlocked)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder private var installButton: some View {
        let needsInstall = !session.readiness.runtimeReady || !session.readiness.modelInstalled
        let button = Button(installTitle) {
            Task { await session.installVoiceModel() }
        }
        .disabled(session.phase.isBusy || session.maintenanceInProgress)
        if needsInstall {
            button.buttonStyle(.borderedProminent)
        } else {
            button.help("Re-check the runtime and model files, repairing anything missing")
        }
    }

    @ViewBuilder private var installMessages: some View {
        if session.isInstalling {
            VStack(alignment: .leading, spacing: 6) {
                if provider == .parakeet, let fraction = MLXModelManager.shared.downloadFraction[parakeet.rawValue] {
                    ProgressView(value: fraction).accessibilityLabel("Voice model download")
                } else {
                    ProgressView().progressViewStyle(.linear).accessibilityLabel("Voice model download")
                }
                Text(downloadMessage).font(.system(size: 11.5)).textSelection(.enabled)
                Text("This can take a few minutes. You can keep using other apps.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            }
        }
        if let error = session.setupError, !session.isInstalling {
            RebuildCallout(tone: .error, message: error) {
                Button("Try again") { Task { await session.installVoiceModel() } }
                    .disabled(session.phase.isBusy || session.maintenanceInProgress)
            }
        }
        if let verification { RebuildCallout(tone: .error, message: verification) }
        if let message = session.verificationMessage {
            RebuildCallout(tone: session.readiness.modelVerificationFailed ? .error : .success, message: message)
        }
    }

    // MARK: Summary

    private var readinessRow: some View {
        let status = readinessStatus
        return HStack(spacing: 10) {
            RebuildStatusLabel(text: status.text, tone: status.tone, busy: status.busy, emphasized: true)
            Spacer()
            Button(session.recordingActionTitle, action: session.toggleRecording)
                .disabled(!session.canToggleRecording)
                .help(session.recordingBlockedReason ?? session.recordingActionTitle)
        }.padding(.horizontal, 4)
    }

    private var storageNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Models and runtime files stay in Application Support. Setup never scans Documents, Desktop or Downloads.")
                .fixedSize(horizontal: false, vertical: true)
            Text(RebuildStorage.root.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
        }
        .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText).padding(.horizontal, 4)
    }

    // MARK: State

    private var modelReady: Bool {
        session.readiness.runtimeReady && session.readiness.modelInstalled && !session.readiness.modelVerificationFailed
    }

    private var installStatus: (text: String, tone: RebuildTone) {
        if session.isInstalling { return ("Installing…", .info) }
        if verifying { return ("Verifying…", .info) }
        if session.readiness.checking { return ("Checking installation…", .info) }
        if !session.readiness.modelInstalled { return ("Not installed", .warning) }
        if !session.readiness.runtimeReady { return ("Local runtime needed", .warning) }
        if session.readiness.modelVerificationFailed { return ("Verification failed", .error) }
        return ("Installed on this Mac", .success)
    }

    /// Summary beside Start recording. Never claims ready while setup work is
    /// running, matching the controls that are blocked meanwhile.
    var readinessStatus: RebuildSetupStatus {
        if session.isInstalling { return .init(text: "Installing voice model…", tone: .info, busy: true) }
        if verifying { return .init(text: "Verifying voice model…", tone: .info, busy: true) }
        if session.maintenanceInProgress { return .init(text: "Model setup in progress…", tone: .info, busy: true) }
        if session.readiness.checking { return .init(text: session.readiness.nextStep, tone: .info, busy: true) }
        return .init(text: session.readiness.nextStep, tone: session.readiness.ready ? .success : .warning, busy: false)
    }

    private var installTitle: String {
        if !session.readiness.runtimeReady { return "Install runtime & voice model" }
        return session.readiness.modelInstalled ? "Check installation" : "Install voice model"
    }

    private var modelActionsBlocked: Bool {
        session.phase.isBusy || session.isInstalling || session.maintenanceInProgress
    }

    private var downloadMessage: String {
        if provider == .local {
            return ModelManager.shared.downloadStages[whisper]?.displayText
                ?? "Downloading and preparing Core ML assets"
        }
        return MLXModelManager.shared.downloadProgress[parakeet.rawValue] ?? "Preparing runtime and model files"
    }
}
