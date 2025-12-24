import SwiftUI

/// Modal for microphone permission education (accessibility handled separately)
internal struct PermissionEducationModal: View {
    let onProceed: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .accessibilityLabel("Microphone permission required")

            VStack(spacing: 12) {
                Text("Microphone Permission Required")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("AudioWhisper needs microphone access to record audio for transcription.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Record audio for transcription", systemImage: "waveform")
                        .foregroundStyle(.blue)
                    Label("Audio is never stored permanently", systemImage: "lock.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }

            HStack(spacing: 12) {
                Button("Not Now") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Dismiss this dialog without granting permission")

                Button("Allow Microphone") {
                    onProceed()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Grant microphone permission")
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 20)
    }
}

/// Modal for accessibility permission (SmartPaste feature)
internal struct AccessibilityPermissionModal: View {
    let onAllow: () -> Void
    let onDontAllow: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)
                .accessibilityLabel("Accessibility permission required")

            VStack(spacing: 12) {
                Text("Enable SmartPaste?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("SmartPaste automatically pastes transcribed text into your apps. This requires Accessibility permission.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Auto-paste into any app", systemImage: "doc.on.clipboard")
                        .foregroundStyle(.blue)
                    Label("Only sends paste commands", systemImage: "keyboard")
                        .foregroundStyle(.secondary)
                    Label("Never reads other apps' content", systemImage: "lock.shield")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }

            HStack(spacing: 12) {
                Button("Don't Allow") {
                    onDontAllow()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Disable SmartPaste and paste manually with Cmd+V")

                Button("Allow") {
                    onAllow()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Open System Settings to grant Accessibility permission")
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 20)
    }
}

internal struct PermissionRecoveryModal: View {
    let onOpenSettings: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(.orange)
                .accessibilityLabel("Warning: Permissions denied")
            
            VStack(spacing: 12) {
                Text("Permissions Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("AudioWhisper needs microphone and accessibility permissions to work properly.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("1.")
                            .fontWeight(.semibold)
                        Text("Click 'Open System Settings' below")
                    }
                    
                    HStack {
                        Text("2.")
                            .fontWeight(.semibold)
                        Text("Enable AudioWhisper in 'Microphone' section")
                    }
                    
                    HStack {
                        Text("3.")
                            .fontWeight(.semibold)
                        Text("Enable AudioWhisper in 'Accessibility' section")
                    }
                }
                .font(.callout)
                .foregroundStyle(.primary)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Dismiss this dialog without opening System Settings")
                
                Button("Open System Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint("Open macOS System Settings to enable permissions")
            }
        }
        .padding(24)
        .frame(width: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(radius: 20)
    }
}
