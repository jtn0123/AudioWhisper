import SwiftUI

struct RebuildModelsView: View {
    @Bindable var session: RebuildSession
    @AppDefault(\.transcriptionProvider) private var provider
    @AppDefault(\.selectedWhisperModel) private var whisper
    @AppDefault(\.selectedParakeetModel) private var parakeet
    @State private var verification: String?
    @State private var verifying = false
    @State private var deletionRequested = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RebuildPageHeading(
                    title: "Set up once. Speak freely.",
                    subtitle:
                        "Two essentials: microphone access and an installed voice model. Everything else is optional.")
                RebuildSection(title: "01 / MICROPHONE") {
                    HStack {
                        Label(
                            session.readiness.microphoneGranted ? "Microphone allowed" : "Microphone access needed",
                            systemImage: session.readiness.microphoneGranted ? "checkmark.circle.fill" : "mic")
                        Spacer()
                        if !session.readiness.microphoneGranted {
                            Button(
                                session.isRequestingMicrophone ? "Waiting for macOS…" : "Allow microphone",
                                action: session.requestMicrophone
                            )
                            .disabled(session.isRequestingMicrophone).buttonStyle(.borderedProminent)
                        }
                    }
                    Text("Requested only when you click Allow. The recording shortcut never opens a permission dialog.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                RebuildSection(title: "02 / VOICE MODEL") {
                    Picker("Engine", selection: $provider) {
                        Text("Parakeet · fast & multilingual").tag(TranscriptionProvider.parakeet)
                            .disabled(!Arch.isAppleSilicon)
                        Text("Whisper · Intel & Apple Silicon").tag(TranscriptionProvider.local)
                    }.pickerStyle(.segmented).disabled(session.isInstalling || session.phase.isBusy || verifying)
                    if provider == .local {
                        Picker("Model", selection: $whisper) {
                            ForEach(WhisperModel.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }.disabled(session.isInstalling || session.phase.isBusy || verifying)
                        Text("Whisper runs through Core ML. Larger models use more memory and disk space.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Model", selection: $parakeet) {
                            Text("v3 · 25 languages").tag(ParakeetModel.v3Multilingual)
                            Text("v2 · English").tag(ParakeetModel.v2English)
                        }.disabled(session.isInstalling || session.phase.isBusy || verifying)
                        Text("Parakeet runs locally on Apple Silicon. Installation includes its Python runtime.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(
                            session.readiness.modelInstalled ? "Installed on this Mac" : "Not installed",
                            systemImage: session.readiness.modelInstalled
                                ? "checkmark.circle.fill" : "arrow.down.circle")
                        Spacer()
                        if session.isInstalling {
                            ProgressView().controlSize(.small)
                            Text("Installing…").font(.subheadline)
                        } else {
                            Button(installTitle) {
                                Task { await session.installVoiceModel() }
                            }.buttonStyle(.borderedProminent).disabled(session.phase.isBusy || verifying)
                        }
                    }
                    if session.isInstalling { Text(downloadMessage).font(.caption).foregroundStyle(.secondary) }
                    if let error = session.setupError {
                        Text(error).font(.subheadline).foregroundStyle(.red).textSelection(.enabled)
                    }
                    if session.readiness.modelInstalled {
                        HStack {
                            Button(verifying ? "Verifying…" : "Verify model") { Task { await verify() } }.disabled(
                                verifying || session.phase.isBusy)
                            Button("Remove selected model", role: .destructive) { deletionRequested = true }
                                .disabled(session.phase.isBusy || session.isInstalling || verifying)
                        }
                    }
                    if let verification { Text(verification).font(.caption).textSelection(.enabled) }
                }
                HStack {
                    Label(
                        session.readiness.nextStep,
                        systemImage: session.readiness.ready ? "checkmark.seal.fill" : "checklist"
                    )
                    .font(.headline)
                    Spacer()
                    if session.readiness.ready { Button("Start recording", action: session.toggleRecording) }
                }.padding(.vertical, 8)
                RebuildSection(title: "APP-MANAGED STORAGE") {
                    Text(
                        "Models and runtime files stay in Application Support. "
                            + "Setup does not scan your Documents, Desktop, or Downloads."
                    )
                    .font(.subheadline).foregroundStyle(.secondary)
                    Text(RebuildStorage.root.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
            }.padding(36)
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

    private var installTitle: String {
        if !session.readiness.runtimeReady { return "Install runtime & voice model" }
        return session.readiness.modelInstalled ? "Check installation" : "Install voice model"
    }

    private var downloadMessage: String {
        if provider == .local {
            return ModelManager.shared.downloadStages[whisper]?.displayText
                ?? "Downloading and preparing Core ML assets"
        }
        return MLXModelManager.shared.downloadProgress[parakeet.rawValue] ?? "Preparing runtime and model files"
    }

    private func verify() async {
        guard !session.phase.isBusy, !session.isInstalling, !session.maintenanceInProgress else { return }
        verifying = true
        session.maintenanceInProgress = true
        verification = nil
        defer {
            verifying = false
            session.maintenanceInProgress = false
        }
        let selectedProvider = provider
        let selectedModel = parakeet
        let selectedWhisper = whisper
        do {
            if selectedProvider == .parakeet {
                let python = try await UvBootstrap.ensureVenv()
                let result = try await ModelVerificationService.verify(
                    scriptName: "verify_parakeet",
                    arguments: [selectedModel.rawValue] + ModelPins.scriptArguments(for: selectedModel.rawValue),
                    pythonPath: python.path, successFallback: "Parakeet is ready"
                )
                verification = result.message
            } else {
                verification =
                    WhisperKitStorage.isModelDownloaded(selectedWhisper)
                    ? "All required Whisper model assets are present. Actual inference is checked separately."
                    : "The model is incomplete. Remove it and install it again."
            }
        } catch { verification = error.localizedDescription }
        await session.refreshSetup()
    }
}
