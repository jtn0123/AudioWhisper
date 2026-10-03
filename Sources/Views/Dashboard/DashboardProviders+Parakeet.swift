import SwiftUI

internal extension DashboardProvidersView {
    // MARK: - Parakeet Section
    @ViewBuilder
    var parakeetCard: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            // Section label
            HStack(spacing: DashboardTheme.Spacing.sm) {
                Text("02")
                    .font(DashboardTheme.Fonts.mono(11, weight: .medium))
                    .foregroundStyle(DashboardTheme.accent)

                Text("PARAKEET SETUP")
                    .font(DashboardTheme.Fonts.sans(11, weight: .semibold))
                    .foregroundStyle(DashboardTheme.inkMuted)
                    .tracking(1.5)
            }

            VStack(spacing: 0) {
                // Environment status - prominent
                environmentStatusSection

                Divider().background(DashboardTheme.rule)

                // Model selection
                modelSelectionSection

                // Verification message — uses the shared DownloadProgressView
                // when the message indicates failure so users get a Retry
                // button consistently across providers. Informational messages
                // continue to use the lightweight info row.
                if let msg = parakeetVerifyMessage, !msg.isEmpty {
                    Divider().background(DashboardTheme.rule)

                    if isVerifyingParakeet {
                        DownloadProgressView(state: .verifying)
                            .padding(DashboardTheme.Spacing.md)
                    } else if msg.localizedCaseInsensitiveContains("fail")
                        || msg.localizedCaseInsensitiveContains("error") {
                        DownloadProgressView(
                            state: .failed(message: msg),
                            onRetry: { verifyParakeetModel() }
                        )
                        .padding(DashboardTheme.Spacing.md)
                    } else {
                        HStack(spacing: DashboardTheme.Spacing.sm) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(DashboardTheme.inkMuted)

                            Text(msg)
                                .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                                .foregroundStyle(DashboardTheme.inkMuted)
                        }
                        .padding(DashboardTheme.Spacing.md)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DashboardTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DashboardTheme.rule, lineWidth: 1)
            )

            // Info footer
            HStack(spacing: DashboardTheme.Spacing.sm) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 11))
                    .foregroundStyle(DashboardTheme.inkFaint)

                Text("Runs locally on Apple Silicon • ~2.5 GB disk space")
                    .font(DashboardTheme.Fonts.sans(11, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkFaint)
            }
        }
    }

    private var environmentStatusSection: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            // Status icon
            ZStack {
                Circle()
                    .fill(envReady
                        ? Color(red: 0.35, green: 0.60, blue: 0.40).opacity(0.12)
                        : DashboardTheme.accent.opacity(0.12))
                    .frame(width: 44, height: 44)

                if isCheckingEnv {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: envReady ? "checkmark" : "arrow.down.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(envReady ? Color(red: 0.35, green: 0.60, blue: 0.40) : DashboardTheme.accent)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(envReady ? "Environment Ready" : "Setup Required")
                    .font(DashboardTheme.Fonts.sans(15, weight: .semibold))
                    .foregroundStyle(DashboardTheme.ink)

                Text("Python dependencies for local neural inference")
                    .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
            }

            Spacer()

            if !envReady {
                Button {
                    runUvSetupSheet(title: "Installing Parakeet dependencies…")
                } label: {
                    Text("Install")
                        .font(DashboardTheme.Fonts.sans(13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(DashboardTheme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    verifyParakeetModel()
                } label: {
                    HStack(spacing: 4) {
                        if isVerifyingParakeet {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isVerifyingParakeet ? "Verifying…" : "Verify")
                            .font(DashboardTheme.Fonts.sans(13, weight: .medium))
                    }
                    .foregroundStyle(DashboardTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DashboardTheme.rule, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isVerifyingParakeet)
            }
        }
        .padding(DashboardTheme.Spacing.lg)
    }

    private var modelSelectionSection: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Model")
                    .font(DashboardTheme.Fonts.sans(14, weight: .medium))
                    .foregroundStyle(DashboardTheme.ink)

                // Surface the selected model's trade-off. `description` existed
                // on ParakeetModel but was never rendered, so the picker gave no
                // hint that v2 is the more accurate English model and v3 trades
                // accuracy for language coverage.
                Text(selectedParakeetModel.description)
                    .font(DashboardTheme.Fonts.sans(12, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Downloaded on first use")
                    .font(DashboardTheme.Fonts.sans(11, weight: .regular))
                    .foregroundStyle(DashboardTheme.inkFaint)
            }

            Spacer()

            Picker("", selection: $selectedParakeetModel) {
                ForEach(ParakeetModel.allCases, id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .labelsHidden()
            .frame(width: 180)
            .accessibilityLabel("Speech-to-text model")
            .accessibilityValue("\(selectedParakeetModel.displayName). \(selectedParakeetModel.description)")
        }
        .padding(DashboardTheme.Spacing.md)
        .onChange(of: selectedParakeetModel) { _, _ in
            Task { await mlxModelManager.ensureParakeetModel() }
        }
    }

    // MARK: - Parakeet Helpers
    private func runUvSetupSheet(title: String, onComplete: (() -> Void)? = nil) {
        setupStatus = title
        setupLogs = ""
        isSettingUp = true
        showSetupSheet = true
        Task {
            do {
                _ = try await UvBootstrap.ensureVenv(userPython: nil) { msg in
                    Task { @MainActor in
                        setupLogs += (setupLogs.isEmpty ? "" : "\n") + msg
                    }
                }
                await MainActor.run {
                    isSettingUp = false
                    setupStatus = "✓ Environment ready"
                    envReady = true
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

    private func venvPythonPath() -> String {
        let appSupport = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let base = appSupport?.appendingPathComponent("AudioWhisper/python_project/.venv/bin/python3").path
        return base ?? ""
    }

    /// Audit item C4: the ~70 lines of Process/Pipe/timeout plumbing that used
    /// to live here now sit in `ModelVerificationService`, which the MLX verify
    /// path shares. This is the view's share of the work: set the busy flags,
    /// call the service, present the result.
    func verifyParakeetModel() {
        isVerifyingParakeet = true
        parakeetVerifyMessage = "Starting verification…"
        let repoToVerify = selectedParakeetModel.repoId

        Task {
            do {
                let py = try await UvBootstrap.ensureVenv(userPython: nil) { _ in }
                await MainActor.run { parakeetVerifyMessage = "Checking model (offline)…" }

                let result = try await ModelVerificationService.verify(
                    scriptName: "verify_parakeet",
                    arguments: [repoToVerify],
                    pythonPath: py.path,
                    successFallback: "Model verified"
                )

                await MainActor.run {
                    isVerifyingParakeet = false
                    parakeetVerifyMessage = result.message
                    if result.succeeded {
                        hasSetupParakeet = true
                        Task { await mlxModelManager.refreshModelList() }
                    }
                }
            } catch {
                await MainActor.run {
                    isVerifyingParakeet = false
                    parakeetVerifyMessage = "Verification error: \(error.localizedDescription)"
                }
            }
        }
    }
}
