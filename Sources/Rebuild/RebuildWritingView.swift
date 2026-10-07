import SwiftUI

/// A finished verify or remove outcome. The tone comes from the authoritative
/// result, never from the wording of the message.
struct RebuildWritingStatus: Equatable {
    let message: String
    let tone: RebuildTone

    static func verification(_ result: ModelVerificationResult) -> Self {
        Self(message: result.message, tone: result.succeeded ? .success : .error)
    }

    static func failure(_ error: Error) -> Self { Self(message: error.localizedDescription, tone: .error) }

    static func removal(stillOnDisk: Bool) -> Self {
        stillOnDisk
            ? Self(message: "Removal failed. The model is still on disk.", tone: .error)
            : Self(message: "Correction model removed.", tone: .success)
    }
}

struct RebuildWritingView: View {
    let session: RebuildSession
    @AppDefault(\.semanticCorrectionMode) private var mode
    @AppDefault(\.semanticCorrectionModelRepo) private var model
    @State private var installing = false
    @State private var status: RebuildWritingStatus?
    @State private var confirmModelDelete = false
    @State private var verifying = false

    var body: some View {
        let installed = MLXModelManager.shared.isModelCachedOnDisk(repo: model)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !Arch.isAppleSilicon {
                    RebuildCallout(tone: .info, message: "Local writing cleanup requires Apple Silicon.")
                }
                enableCard(installed: installed)
                modelCard(installed: installed)
                Text(
                    "One conservative policy in every app: grammar, punctuation and filler words are fixed without "
                        + "changing meaning. Compare or restore the original on Record and in the Library."
                )
                .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.horizontal, 4)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 860, alignment: .leading)
        }
        .disabled(session.phase.isBusy)
        .onChange(of: model) { _, selected in
            status = nil
            if !MLXModelManager.shared.isModelCachedOnDisk(repo: selected) { mode = .off }
        }
        .confirmationDialog("Remove these shared correction weights?", isPresented: $confirmModelDelete) {
            Button("Remove model", role: .destructive) {
                let selected = model
                Task {
                    guard !session.phase.isBusy, !session.isInstalling,
                        !session.maintenanceInProgress
                    else { return }
                    installing = true
                    session.maintenanceInProgress = true
                    defer {
                        installing = false
                        session.maintenanceInProgress = false
                    }
                    mode = .off
                    await MLXModelManager.shared.deleteModel(selected)
                    status = .removal(stillOnDisk: MLXModelManager.shared.isModelCachedOnDisk(repo: selected))
                }
            }
        }
    }

    private var installer: RebuildWritingInstaller { session.writingInstaller }
    private var actionsBlocked: Bool { installing || verifying || installer.isRunning }

    private func enableCard(installed: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Clean up grammar, punctuation and filler words").font(.system(size: 13, weight: .semibold))
                Text(
                    installed
                        ? "Runs after each transcription. If cleanup can’t safely keep your words, the original is used."
                        : "Install a correction model below to turn this on."
                )
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Toggle(
                "Clean up grammar, punctuation and filler words",
                isOn: Binding(get: { mode == .localMLX }, set: { mode = $0 ? .localMLX : .off })
            )
            .toggleStyle(.switch).labelsHidden()
            .disabled(!Arch.isAppleSilicon || !installed)
        }.rebuildCard()
    }

    private func modelCard(installed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Correction model").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
            RebuildFormRow(label: "Model") {
                Picker("Correction model", selection: $model) {
                    ForEach(MLXModelManager.recommendedModels) {
                        Text(modelLabel($0)).tag($0.repo)
                    }
                }
                .labelsHidden().frame(maxWidth: 360)
                .disabled(actionsBlocked || !Arch.isAppleSilicon)
                if let selected = MLXModelManager.recommendedModels.first(where: { $0.repo == model }) {
                    Text("\(selected.description). Download \(selected.estimatedSize); memory estimates exclude your other apps.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider()
            installRow(installed: installed)
            if installer.isRunning { progress }
            if let status {
                RebuildCallout(tone: status.tone, message: status.message)
            } else if let message = installer.status(for: model) {
                RebuildCallout(tone: Self.tone(for: message), message: message)
            }
        }.rebuildCard()
    }

    private func installRow(installed: Bool) -> some View {
        HStack(spacing: 8) {
            RebuildStatusLabel(
                text: installer.isRunning ? "Installing…" : verifying ? "Verifying…"
                    : installed ? "Installed on this Mac" : "Not installed",
                tone: installed ? .success : .info, busy: installer.isRunning || verifying)
            Spacer()
            if installed {
                Button(verifying ? "Verifying…" : "Verify correction model") { Task { await verifyModel() } }
                    .disabled(actionsBlocked)
                Button("Remove…", role: .destructive) { confirmModelDelete = true }
                    .disabled(actionsBlocked)
                    .accessibilityLabel("Remove correction model")
            } else if !installer.isRunning {
                Button("Install correction model") {
                    status = nil
                    installer.start(model, session: session)
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(actionsBlocked || !Arch.isAppleSilicon)
            }
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = installer.fraction {
                ProgressView(value: fraction).accessibilityLabel("Correction model download")
            } else {
                ProgressView().progressViewStyle(.linear).accessibilityLabel("Correction model download")
            }
            HStack(spacing: 8) {
                Text(installer.progress ?? "Preparing download…").font(.system(size: 11.5)).textSelection(.enabled)
                Spacer()
                if let fraction = installer.fraction {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
                }
                Button(installer.cancelling ? "Cancelling…" : "Cancel install") {
                    Task { await installer.cancel() }
                }.disabled(installer.cancelling)
            }
        }
    }

    /// Tone for the installer's terminal text. Only the installer's own
    /// affirmative outcome is success; anything unrecognized stays neutral.
    static func tone(for message: String) -> RebuildTone {
        if message == RebuildWritingInstaller.installedMessage { return .success }
        let text = message.lowercased()
        if text.hasPrefix("error") || text.contains("failed") || text.contains("did not finish") { return .error }
        return .info
    }

    private func modelLabel(_ entry: MLXModel) -> String {
        let recommendation = entry.repo == AppDefaults.defaultSemanticCorrectionModelRepo ? " · Recommended" : ""
        return entry.displayName + recommendation
    }

    private func verifyModel() async {
        guard !session.phase.isBusy, !session.isInstalling, !session.maintenanceInProgress else { return }
        verifying = true
        session.maintenanceInProgress = true
        status = nil
        let selected = model
        defer {
            verifying = false
            session.maintenanceInProgress = false
        }
        do {
            let python = try await UvBootstrap.ensureVenv()
            let result = try await ModelVerificationService.verify(
                scriptName: "verify_mlx", arguments: [selected] + ModelPins.scriptArguments(for: selected),
                pythonPath: python.path, successFallback: "Correction model is ready")
            status = .verification(result)
        } catch { status = .failure(error) }
    }
}
