import AppKit
import SwiftUI

struct RebuildWritingView: View {
    let session: RebuildSession
    @AppDefault(\.semanticCorrectionMode) private var mode
    @AppDefault(\.semanticCorrectionModelRepo) private var model
    @State private var installing = false
    @State private var status: String?
    @State private var confirmModelDelete = false
    @State private var verifying = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RebuildPageHeading(
                    title: "Sound like yourself.",
                    subtitle:
                        "Optional local grammar and punctuation cleanup. "
                        + "The original transcript survives if cleanup fails."
                )
                RebuildSection(title: "LOCAL WRITING CLEANUP") {
                    Picker("Correction model", selection: $model) {
                        ForEach(MLXModelManager.recommendedModels) {
                            Text(modelLabel($0)).tag($0.repo)
                        }
                    }.disabled(installing || verifying || session.writingInstaller.isRunning || !Arch.isAppleSilicon)
                    if let selected = MLXModelManager.recommendedModels.first(where: { $0.repo == model }) {
                        Text(selected.description)
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Download: \(selected.estimatedSize). Memory estimates exclude your other apps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle(
                        "Clean up grammar, punctuation and filler words",
                        isOn: Binding(
                            get: { mode == .localMLX }, set: { mode = $0 ? .localMLX : .off }
                        )
                    ).disabled(!Arch.isAppleSilicon || !MLXModelManager.shared.isModelCachedOnDisk(repo: model))
                    HStack {
                        Text(
                            MLXModelManager.shared.isModelCachedOnDisk(repo: model)
                                ? "Correction model installed" : "Install the selected model to enable cleanup"
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Install correction model") {
                            session.writingInstaller.start(model, session: session)
                        }.disabled(installing || verifying || session.writingInstaller.isRunning || !Arch.isAppleSilicon)

                    }
                    if session.writingInstaller.isRunning {
                        VStack(alignment: .leading, spacing: 8) {
                            if let fraction = session.writingInstaller.fraction {
                                ProgressView(value: fraction)
                            } else { ProgressView().controlSize(.small) }
                            HStack {
                                Text(session.writingInstaller.progress ?? "Preparing download…")
                                    .font(.caption).textSelection(.enabled)
                                Spacer()
                                Button(session.writingInstaller.cancelling ? "Cancelling…" : "Cancel install") {
                                    Task { await session.writingInstaller.cancel() }
                                }.disabled(session.writingInstaller.cancelling)
                            }
                        }
                    }
                    if let status = session.writingInstaller.status {
                        Text(status).font(.caption).textSelection(.enabled)
                    }
                    if MLXModelManager.shared.isModelCachedOnDisk(repo: model) {
                        HStack {
                            Button(verifying ? "Verifying…" : "Verify correction model") {
                                Task { await verifyModel() }
                            }
                            .disabled(installing || verifying || session.writingInstaller.isRunning)
                            Button("Remove correction model", role: .destructive) { confirmModelDelete = true }
                                .disabled(installing || verifying || session.writingInstaller.isRunning)
                        }
                    }
                    if !Arch.isAppleSilicon {
                        Text("Local writing cleanup requires Apple Silicon.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let status { Text(status).font(.caption).textSelection(.enabled) }
                }
            }.padding(36)
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
                    status =
                        MLXModelManager.shared.isModelCachedOnDisk(repo: selected)
                        ? "Removal failed. The model is still on disk." : "Correction model removed."
                }
            }
        }

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
            status = result.message
        } catch { status = error.localizedDescription }
    }

}
