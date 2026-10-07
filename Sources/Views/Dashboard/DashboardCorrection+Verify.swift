import SwiftUI

extension DashboardCorrectionView {
    // MARK: - Verify Row
    var verifyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if isVerifyingMLX { ProgressView().controlSize(.small) }
                Button(isVerifyingMLX ? "Verifying…" : "Verify MLX Model") {
                    verifyMLXModel()
                }
                .buttonStyle(.bordered)
                .tint(DashboardTheme.accent)
                .disabled(isVerifyingMLX)

                if let msg = mlxVerifyMessage,
                   !msg.isEmpty,
                   !msg.localizedCaseInsensitiveContains("fail"),
                   !msg.localizedCaseInsensitiveContains("error") {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(DashboardTheme.inkMuted)
                }
                Spacer()
            }

            // Surface verification failures via the shared DownloadProgressView
            // so users see a consistent failure UI with a Retry affordance.
            if let msg = mlxVerifyMessage,
               !msg.isEmpty,
               !isVerifyingMLX,
               msg.localizedCaseInsensitiveContains("fail")
                || msg.localizedCaseInsensitiveContains("error") {
                DownloadProgressView(
                    state: .failed(message: msg),
                    onRetry: { verifyMLXModel() }
                )
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Helpers (copied from SettingsView)
    func runUvSetupSheet(title: String, onComplete: (() -> Void)? = nil) {
        setupStatus = title
        setupLogs = ""
        isSettingUp = true
        showSetupSheet = true
        Task {
            do {
                _ = try await UvBootstrap.ensureVenv(userPython: nil, forceRefresh: true) { msg in
                    Task { @MainActor in
                        setupLogs += (setupLogs.isEmpty ? "" : "\n") + msg
                    }
                }
                await MainActor.run {
                    isSettingUp = false
                    setupStatus = "✓ Environment ready"
                    envReady = true
                    hasSetupLocalLLM = true
                    hasSetupParakeet = true
                }
                try? await Task.sleep(for: .milliseconds(600))
                await MainActor.run {
                    showSetupSheet = false
                    onComplete?()
                }
            } catch {
                await MainActor.run {
                    isSettingUp = false
                    setupStatus = "✗ Setup failed"
                    let msg = error.localizedDescription.isEmpty ? String(describing: error) : error.localizedDescription
                    setupLogs += (setupLogs.isEmpty ? "" : "\n") + "Error: \(msg)"
                    envReady = false
                }
            }
        }
    }

    func checkEnvReady() {
        isCheckingEnv = true
        Task {
            let fm = FileManager.default
            let py = venvPythonPath()
            var ready = false
            if fm.isExecutableFile(atPath: py) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: py)
                process.arguments = ["-c", "import mlx_lm; print('OK')"]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 { ready = true }
                } catch {
                    ready = false
                }
            }
            await MainActor.run {
                self.envReady = ready
                self.isCheckingEnv = false
                if ready {
                    self.hasSetupParakeet = true
                    self.hasSetupLocalLLM = true
                }
            }
        }
    }

    func venvPythonPath() -> String {
        let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = appSupport?.appendingPathComponent("AudioWhisper/python_project/.venv/bin/python3").path
        return base ?? ""
    }

    /// Audit item C4: shares `ModelVerificationService` with the Parakeet verify
    /// path. The two used to be verbatim copies of the same Process/Pipe/timeout
    /// plumbing, differing only in the script name and success wording.
    func verifyMLXModel() {
        isVerifyingMLX = true
        mlxVerifyMessage = "Checking model (offline)…"
        let repo = semanticCorrectionModelRepo

        Task {
            do {
                let py = try await UvBootstrap.ensureVenv(userPython: nil) { _ in }

                let result = try await ModelVerificationService.verify(
                    scriptName: "verify_mlx",
                    // The pin, so a cache miss downloads the commit this build ships.
                    arguments: [repo] + ModelPins.scriptArguments(for: repo),
                    pythonPath: py.path,
                    successFallback: "Model verified"
                )

                await MainActor.run {
                    isVerifyingMLX = false
                    mlxVerifyMessage = result.message
                    if result.succeeded {
                        Task { await modelManager.refreshModelList() }
                    }
                }
            } catch {
                await MainActor.run {
                    isVerifyingMLX = false
                    mlxVerifyMessage = "Verification error: \(error.localizedDescription)"
                }
            }
        }
    }
}
