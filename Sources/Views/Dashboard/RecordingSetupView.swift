import SwiftUI
import AppKit

/// One place to finish the two requirements for recording. Optional paste
/// permissions stay in General/Permissions rather than interrupting setup.
internal struct RecordingSetupView: View {
    @Environment(PermissionManager.self) private var permissions
    @State private var setup = RecordingSetupState.shared
    @AppDefault(\.transcriptionProvider) private var provider
    @AppDefault(\.selectedWhisperModel) private var whisperModel
    @AppDefault(\.selectedParakeetModel) private var parakeetModel

    var body: some View {
        ScrollableContent {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording setup")
                        .font(DashboardTheme.Fonts.serif(28, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Finish these two steps before your first recording. Everything runs on your Mac.")
                        .foregroundStyle(.secondary)
                }

                setupCard(number: "1", title: "Microphone", complete: permissions.microphonePermissionState == .granted) {
                    Text(microphoneMessage)
                    if permissions.microphonePermissionState != .granted {
                        Button(microphoneButtonTitle) {
                            permissions.requestMicrophonePermission()
                        }
                        .buttonStyle(PaperAccentButtonStyle())
                        .disabled(permissions.microphonePermissionState == .requesting
                                  || permissions.microphonePermissionState == .restricted)
                    }
                }

                setupCard(number: "2", title: "Voice model", complete: setup.modelRequirement.isReady) {
                    Picker("Transcription engine", selection: $provider) {
                        Text("Local Whisper").tag(TranscriptionProvider.local)
                        if RecordingSetupState.supportsParakeet {
                            Text("Parakeet").tag(TranscriptionProvider.parakeet)
                        }
                    }
                    .disabled(setup.isInstalling)
                    if provider == .local {
                        Picker("Voice model", selection: $whisperModel) {
                            ForEach(WhisperModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .disabled(setup.isInstalling)
                    } else {
                        Picker("Voice model", selection: $parakeetModel) {
                            ForEach(ParakeetModel.allCases, id: \.self) { model in
                                Text(model.displayName).tag(model)
                            }
                        }
                        .disabled(setup.isInstalling)
                    }

                    Text(setup.modelRequirement.isReady
                         ? "Your selected voice model is installed."
                         : setup.modelRequirement.message)
                        .foregroundStyle(.secondary)

                    if setup.isInstalling {
                        ProgressView("Installing your selected model…")
                        Text("Keep AudioWhisper open. You can use other apps while the download finishes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if !setup.modelRequirement.isReady {
                        Button(provider == .local ? "Download voice model" : "Install Parakeet and voice model") {
                            Task { await setup.installSelectedModel() }
                        }
                        .buttonStyle(PaperAccentButtonStyle())
                        .disabled(setup.isRefreshing || setup.modelRequirement == .unsupportedHardware)
                    }
                    if let installError = setup.installError {
                        Text(installError)
                            .foregroundStyle(DashboardTheme.destructive)
                            .textSelection(.enabled)
                    }
                }

                Label(setup.requirement.message,
                      systemImage: setup.requirement.isReady ? "checkmark.circle.fill" : "info.circle")
                    .font(.headline)
                    .foregroundStyle(setup.requirement.isReady ? DashboardTheme.success : DashboardTheme.ink)
                Text(setup.requirement.isReady
                     ? "Use your recording shortcut or Start Recording in the menu bar."
                     : "The recording shortcut will bring you here until setup is complete.")
                    .foregroundStyle(.secondary)
                Text("Smart Paste is optional. Without it, completed transcripts are copied to your clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Check setup again") { Task { await setup.refresh() } }
                    .disabled(setup.isRefreshing || setup.isInstalling)
            }
            .padding(DashboardTheme.Spacing.xl)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .background(DashboardTheme.pageBg)
        .task(id: "\(provider.rawValue):\(whisperModel.rawValue):\(parakeetModel.rawValue)") {
            await setup.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await setup.refresh() }
        }
    }

    private var microphoneMessage: String {
        switch permissions.microphonePermissionState {
        case .granted: return "Microphone access is allowed."
        case .requesting: return "Choose Allow in the macOS microphone prompt."
        case .denied: return "Enable AudioWhisper in System Settings → Privacy & Security → Microphone, then return here."
        case .restricted: return "This Mac restricts microphone access. Check with its administrator."
        case .unknown, .notRequested: return "Allow AudioWhisper to record your voice. macOS will ask once."
        }
    }

    private var microphoneButtonTitle: String {
        permissions.microphonePermissionState == .denied ? "Open Microphone settings" : "Allow microphone"
    }

    private func setupCard<Content: View>(
        number: String, title: String, complete: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(number).font(.headline).foregroundStyle(DashboardTheme.accent)
                Text(title).font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                if complete { Image(systemName: "checkmark.circle.fill").foregroundStyle(DashboardTheme.success) }
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.md).fill(DashboardTheme.cardBg))
        .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.md).stroke(DashboardTheme.rule, lineWidth: 0.5))
    }

}
