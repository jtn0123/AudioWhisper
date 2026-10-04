import AVFoundation
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct RebuildPreferencesView: View {
    @AppDefault(\.immediateRecording) private var express
    @AppDefault(\.enableSmartPaste) private var smartPaste
    @AppDefault(\.playCompletionSound) private var sound
    @AppDefault(\.selectedMicrophone) private var microphone
    @AppDefault(\.autoBoostMicrophoneVolume) private var boost
    @AppDefault(\.pressAndHoldEnabled) private var holdEnabled
    @AppDefault(\.pressAndHoldKeyIdentifier) private var holdKey
    @AppDefault(\.pressAndHoldMode) private var holdMode
    @AppDefault(\.transcriptionHistoryEnabled) private var history
    @AppDefault(\.transcriptionRetentionPeriod) private var retention
    @AppDefault(\.waveformStyle) private var waveform
    @AppDefault(\.visualIntensity) private var intensity
    @AppDefault(\.startAtLogin) private var login
    @AppDefault(\.maxModelStorageGB) private var storageLimit
    @AppStorage("rebuild.shortcutEnabled", store: AppDefaults.defaults) private var shortcutEnabled = false
    @AppStorage("rebuild.appearance", store: AppDefaults.defaults) private var appearance = "system"
    @State private var microphones: [AVCaptureDevice] = []
    @State private var resetUsage = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RebuildPageHeading(
                    title: "Make it your own.",
                    subtitle:
                        "Optional conveniences stay optional. Recording only requires a microphone and voice model.")
                RebuildSection(title: "SHORTCUTS & RECORDING") {
                    Toggle("Enable the rebuild’s recording shortcut", isOn: $shortcutEnabled)
                    Text("Keep this off while the original app uses the same shortcut.").font(.caption).foregroundStyle(
                        .secondary)
                    KeyboardShortcuts.Recorder("Recording shortcut", name: .rebuildRecording) { _ in settingsChanged() }
                    Toggle("Express Mode · record without showing the overlay", isOn: $express)
                    Toggle("Record while holding a modifier key", isOn: $holdEnabled)
                    if holdEnabled {
                        Picker("Modifier", selection: $holdKey) {
                            ForEach(PressAndHoldKey.allCases) { Text($0.displayName).tag($0.rawValue) }
                        }
                        Picker("Behavior", selection: $holdMode) {
                            ForEach(PressAndHoldMode.allCases) { Text($0.displayName).tag($0.rawValue) }
                        }
                        Text("Requires Accessibility access. No access is requested automatically.").font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Microphone", selection: $microphone) {
                        Text("System default").tag("")
                        ForEach(microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    Toggle("Boost microphone input while recording", isOn: $boost)
                    Toggle("Play a completion sound", isOn: $sound)
                }
                RebuildSection(title: "DELIVERY & PERMISSIONS") {
                    Toggle("Smart Paste · paste into the app I recorded from", isOn: $smartPaste)
                    Text(
                        "Text always reaches your clipboard. Smart Paste requires Accessibility "
                            + "and uses only the captured destination."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Label(
                            AccessibilityPermissionManager().checkPermission()
                                ? "Accessibility allowed" : "Accessibility not enabled", systemImage: "hand.raised")
                        Spacer()
                        Button("Open Accessibility settings") {
                            if let url = URL(
                                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                RebuildSection(title: "LIBRARY & PRIVACY") {
                    Toggle("Save transcripts to my local library", isOn: $history)
                    Picker("Keep transcripts for", selection: $retention) {
                        ForEach(RetentionPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Text(
                        "The rebuild has its own empty library. It does not read or change the original app’s transcripts."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                    Stepper("Whisper storage limit: \(Int(storageLimit)) GB", value: $storageLimit, in: 2...30, step: 1)
                }
                RebuildSection(title: "APPEARANCE & STARTUP") {
                    Picker("Appearance", selection: $appearance) {
                        Text("Follow macOS").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented)
                    Picker("Recorder visual", selection: $waveform) {
                        ForEach(WaveformStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Motion intensity", selection: $intensity) {
                        ForEach(VisualIntensity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text("The recorder respects macOS Reduce Motion. Normal windows stay on desktop Spaces.").font(
                        .caption
                    ).foregroundStyle(.secondary)
                    Toggle("Open the rebuild at login", isOn: $login)
                }
                RebuildSection(title: "SUPPORT & USAGE") {
                    Button("Copy setup diagnostics") {
                        Task {
                            let report = await RebuildDiagnostics.snapshot(context: "application")
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                            if let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) {
                                PasteManager.copyToClipboard(text)
                                message = "Setup diagnostics copied. No transcripts or history are included."
                            }
                        }
                    }
                    Button("Recalculate usage from saved history") {
                        Task {
                            do { try await UsageMetricsStore.shared.rebuildFromHistory() } catch {
                                message = "Usage could not be recalculated: \(error.localizedDescription)"
                            }
                        }
                    }.disabled(!history)
                    Button("Reset usage totals…", role: .destructive) { resetUsage = true }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
                Text("Build \(VersionInfo.gitHash) · Development preview").font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }.padding(36)
        }
        .confirmationDialog("Reset usage totals? Your saved transcripts stay in the library.", isPresented: $resetUsage) {
            Button("Reset totals", role: .destructive) { UsageMetricsStore.shared.reset() }
        }
        .task {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
            microphones =
                AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
                .devices
        }
        .onChange(of: shortcutEnabled) { _, _ in settingsChanged() }
        .onChange(of: holdEnabled) { _, _ in settingsChanged() }
        .onChange(of: holdKey) { _, _ in settingsChanged() }
        .onChange(of: holdMode) { _, _ in settingsChanged() }
        .onChange(of: login) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                message = nil
            } catch {
                message = "Login setting could not be updated: \(error.localizedDescription)"
                login = SMAppService.mainApp.status == .enabled
            }
        }
        .onChange(of: retention) { _, _ in
            Task {
                do { try await DataManager.shared.cleanupExpiredRecords() } catch {
                    message = "Retention cleanup failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func settingsChanged() { NotificationCenter.default.post(name: .rebuildSettingsChanged, object: nil) }
}
