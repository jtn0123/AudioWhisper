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
    @AppStorage("rebuild.shortcutEnabled", store: AppDefaults.defaults) private var shortcutEnabled = false
    @AppStorage("rebuild.appearance", store: AppDefaults.defaults) private var appearance = "system"
    @State private var microphones: [AVCaptureDevice] = []
    @State private var message: String?
    @State private var accessibilityAllowed = AccessibilityPermissionManager().checkPermission()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                recordingSection
                microphoneSection
                deliverySection
                librarySection
                appearanceSection
                RebuildAdvancedSection(message: $message)
                if let message {
                    RebuildCallout(tone: .info, message: message) {
                        Button("Dismiss") { self.message = nil }.buttonStyle(.rebuildLink)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 860, alignment: .leading)
        }
        .task {
            refreshAccessibility()
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else { return }
            microphones =
                AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
                .devices
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
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

    // MARK: Sections

    private var recordingSection: some View {
        RebuildSection(
            title: "Recording",
            caption: "Pick keys other apps aren’t using. Assigning new keys turns the shortcut on."
        ) {
            RebuildFormRow(label: "Shortcut") {
                HStack(spacing: 12) {
                    KeyboardShortcuts.Recorder(for: .rebuildRecording) { shortcut in
                        if shortcut != nil && !shortcutEnabled { shortcutEnabled = true }
                        settingsChanged()
                    }
                    .accessibilityLabel("Recording shortcut")
                    Toggle("Enable recording shortcut", isOn: $shortcutEnabled)
                }
            }
            RebuildFormRow(label: "Hold to record") {
                Toggle("Record while holding a modifier key", isOn: $holdEnabled)
                if holdEnabled {
                    HStack(spacing: 10) {
                        Picker("Modifier", selection: $holdKey) {
                            ForEach(PressAndHoldKey.allCases) { Text($0.displayName).tag($0.rawValue) }
                        }.fixedSize()
                        Picker("Behavior", selection: $holdMode) {
                            ForEach(PressAndHoldMode.allCases) { Text($0.displayName).tag($0.rawValue) }
                        }.fixedSize()
                    }
                    Text("Requires Accessibility access. No access is requested automatically.")
                        .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                }
            }
            RebuildFormRow(label: "Overlay") {
                Toggle("Express Mode · record without showing the overlay", isOn: $express)
            }
        }
    }

    private var microphoneSection: some View {
        RebuildSection(title: "Microphone & feedback") {
            RebuildFormRow(label: "Input") {
                Picker("Microphone", selection: $microphone) {
                    Text("System default").tag("")
                    ForEach(microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                .labelsHidden().frame(maxWidth: 320)
                Toggle("Boost microphone input while recording", isOn: $boost)
            }
            RebuildFormRow(label: "Sound") {
                Toggle("Play a completion sound", isOn: $sound)
            }
        }
    }

    private var deliverySection: some View {
        RebuildSection(
            title: "Delivery",
            caption: "Text always reaches your clipboard. Smart Paste uses only the app you recorded from."
        ) {
            RebuildFormRow(label: "Smart Paste") {
                Toggle("Paste into the app I recorded from", isOn: $smartPaste)
            }
            RebuildFormRow(label: "Accessibility") {
                HStack(spacing: 8) {
                    RebuildStatusLabel(
                        text: accessibilityAllowed ? "Allowed" : "Not enabled",
                        tone: accessibilityAllowed ? .success : (smartPaste || holdEnabled ? .warning : .info))
                    Spacer(minLength: 8)
                    Button("Check access", action: refreshAccessibility)
                    Button("Open System Settings") {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .accessibilityLabel("Open Accessibility settings")
                }
                Text("Needed for Smart Paste and hold-to-record. Nothing is requested automatically.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            }
        }
    }

    private var librarySection: some View {
        RebuildSection(title: "Library & privacy", caption: "Saved transcripts stay on this Mac. Saving is off by default.") {
            RebuildFormRow(label: "History") {
                Toggle("Save transcripts to my local library", isOn: $history)
            }
            RebuildFormRow(label: "Keep for") {
                Picker("Keep transcripts for", selection: $retention) {
                    ForEach(RetentionPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private var appearanceSection: some View {
        RebuildSection(title: "Appearance & startup") {
            RebuildFormRow(label: "Appearance") {
                Picker("Appearance", selection: $appearance) {
                    Text("Follow macOS").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            RebuildFormRow(label: "Recorder") {
                HStack(spacing: 10) {
                    Picker("Recorder visual", selection: $waveform) {
                        ForEach(WaveformStyle.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                    Picker("Motion intensity", selection: $intensity) {
                        ForEach(VisualIntensity.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                Text("Visual style and motion. The recorder respects macOS Reduce Motion.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
            }
            RebuildFormRow(label: "Startup") {
                Toggle("Open AudioWhisper at login", isOn: $login)
            }
        }
    }

    // MARK: Actions

    private func settingsChanged() { NotificationCenter.default.post(name: .rebuildSettingsChanged, object: nil) }

    private func refreshAccessibility() {
        let allowed = AccessibilityPermissionManager().checkPermission()
        guard allowed != accessibilityAllowed else { return }
        accessibilityAllowed = allowed
        settingsChanged()
    }
}

/// Collapsed storage, diagnostics and usage-total tools. Results are reported
/// through the shared Preferences message.
private struct RebuildAdvancedSection: View {
    @Binding var message: String?
    @AppDefault(\.transcriptionHistoryEnabled) private var history
    @AppDefault(\.maxModelStorageGB) private var storageLimit
    @State private var resetUsage = false
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 12) {
                    RebuildFormRow(label: "Whisper storage") {
                        Stepper("Limit: \(Int(storageLimit)) GB", value: $storageLimit, in: 2...30, step: 1)
                            .fixedSize()
                    }
                    RebuildFormRow(label: "Support") {
                        Button("Copy setup diagnostics", action: copyDiagnostics)
                            .help("Copies setup details only. No transcripts or history are included.")
                    }
                    RebuildFormRow(label: "Usage totals") {
                        HStack(spacing: 8) {
                            Button("Recalculate from saved history", action: recalculateUsage).disabled(!history)
                            Button("Reset…", role: .destructive) { resetUsage = true }
                                .accessibilityLabel("Reset usage totals")
                        }
                    }
                    Text("Build \(VersionInfo.gitHash) · Development preview")
                        .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(RebuildTheme.secondaryText)
                        .textSelection(.enabled)
                }.padding(.top, 12)
            } label: {
                // The macOS disclosure label is not clickable by itself.
                Button {
                    showAdvanced.toggle()
                } label: {
                    HStack {
                        Text("Advanced & support").font(.system(size: 13, weight: .semibold))
                        Text("Storage limit, diagnostics, usage totals").font(.system(size: 12))
                            .foregroundStyle(RebuildTheme.secondaryText)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Advanced and support")
                .accessibilityValue(showAdvanced ? "Expanded" : "Collapsed")
            }
        }
        .rebuildCard()
        .confirmationDialog("Reset usage totals? Your saved transcripts stay in the library.", isPresented: $resetUsage) {
            Button("Reset totals", role: .destructive) { UsageMetricsStore.shared.reset() }
        }
    }

    private func copyDiagnostics() {
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

    private func recalculateUsage() {
        Task {
            do { try await UsageMetricsStore.shared.rebuildFromHistory() } catch {
                message = "Usage could not be recalculated: \(error.localizedDescription)"
            }
        }
    }
}
