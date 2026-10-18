import KeyboardShortcuts
import SwiftUI

struct RebuildPreferencesView: View {
    @AppDefault(\.liveTranscriptionPreview) private var livePreview
    @AppDefault(\.transcriptionProvider) private var provider
    @AppDefault(\.immediateRecording) private var express
    @AppDefault(\.enableSmartPaste) private var smartPaste
    @AppDefault(\.playCompletionSound) private var sound
    @AppDefault(\.microphoneRanking) private var ranking
    @AppDefault(\.lowerOtherAudioWhileRecording) private var lowerOthers
    @AppDefault(\.keepMicrophoneReady) private var keepReady
    @AppDefault(\.pressAndHoldEnabled) private var holdEnabled
    @AppDefault(\.pressAndHoldKeyIdentifier) private var holdKey
    @AppDefault(\.pressAndHoldMode) private var holdMode
    @AppDefault(\.transcriptionHistoryEnabled) private var history
    @AppDefault(\.transcriptionRetentionPeriod) private var retention
    @AppDefault(\.startAtLogin) private var login
    @AppStorage("rebuild.shortcutEnabled", store: AppDefaults.defaults) private var shortcutEnabled = false
    @AppStorage("rebuild.appearance", store: AppDefaults.defaults) private var appearance = "system"
    @State private var inputs: RebuildMicrophoneInputs
    @State private var state: RebuildPreferencesState
    private var message: String? {
        get { state.message }
        nonmutating set { state.message = newValue }
    }
    private var accessibilityAllowed: Bool { state.accessibilityAllowed }
    var session: RebuildSession?

    @MainActor
    init(
        session: RebuildSession? = nil, inputs: RebuildMicrophoneInputs? = nil,
        state: RebuildPreferencesState? = nil
    ) {
        self.session = session
        _inputs = State(initialValue: inputs ?? RebuildMicrophoneInputs())
        _state = State(initialValue: state ?? RebuildPreferencesState())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                recordingSection
                microphoneSection
                deliverySection
                librarySection
                appearanceSection
                RebuildAdvancedSection(state: state, connected: inputs.devices, timing: session?.timing)
                if let message {
                    RebuildCallout(tone: state.messageTone, message: message) {
                        Button("Dismiss") { self.message = nil }.buttonStyle(.rebuildLink)
                    }
                }
            }
            .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 860, alignment: .leading)
        }
        .task {
            refreshAccessibility()
            inputs.startObserving()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
        }
        .onChange(of: session?.readiness.microphoneGranted) { _, _ in inputs.refresh() }
        .onChange(of: shortcutEnabled) { _, _ in settingsChanged() }
        .onChange(of: holdEnabled) { _, _ in settingsChanged() }
        .onChange(of: holdKey) { _, _ in settingsChanged() }
        .onChange(of: holdMode) { _, _ in settingsChanged() }
        .onChange(of: login) { _, enabled in
            do {
                try state.effects.changeLogin(enabled)
                message = nil
            } catch {
                state.messageTone = .error
                message = "Login setting could not be updated: \(error.localizedDescription)"
                login = state.effects.loginEnabled()
            }
        }
        .onChange(of: retention) { _, _ in
            Task {
                do { try await state.effects.cleanupRetention() } catch {
                    state.messageTone = .error
                    message = "Retention cleanup failed: \(error.localizedDescription)"
                }
            }
        }
        .onChange(of: keepReady) { _, _ in settingsChanged() }
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
            RebuildFormRow(label: "Live preview") {
                Toggle("Show words while I speak", isOn: $livePreview).disabled(provider != .parakeet)
                Text(provider == .parakeet
                     ? "A rolling, on-device draft of recent speech. Final text is transcribed when you stop."
                     : "Choose Parakeet in Models & setup to use live preview.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RebuildFormRow(label: "Overlay") {
                Toggle("Express Mode · record without showing the overlay", isOn: $express)
            }
        }
    }

    private var microphoneSection: some View {
        RebuildSection(title: "Microphone & feedback") {
            RebuildFormRow(label: "Input") {
                RebuildPreferredMicrophonePicker(ranking: $ranking, connected: inputs.devices)
                Text("Set fallback order in Advanced & support.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                Toggle("Keep the microphone ready between recordings", isOn: $keepReady)
                Text("Reduces startup delay and keeps a brief moment before the shortcut. "
                     + "The microphone stays on while idle; audio stays in a short memory buffer until you record. "
                     + "Bluetooth headsets use normal startup.")
                    .font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            RebuildFormRow(label: "Sound") {
                Toggle("Play a completion sound", isOn: $sound)
                Toggle("Lower other audio while recording", isOn: $lowerOthers)
            }
        }
    }

    private var deliverySection: some View {
        RebuildSection(
            title: "Delivery",
            caption: "Text always reaches your clipboard first. Smart Paste uses only the app you recorded from."
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
                    Button("Open System Settings", action: state.effects.openAccessSettings)
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
                .labelsHidden().fixedSize().disabled(!history)
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
            RebuildFormRow(label: "Startup") {
                Toggle("Open AudioWhisper at login", isOn: $login)
            }
        }
    }

    // MARK: Actions

    private func settingsChanged() { NotificationCenter.default.post(name: .rebuildSettingsChanged, object: nil) }

    private func refreshAccessibility() {
        inputs.refresh()
        guard state.refreshAccess() else { return }
        settingsChanged()
    }
}

/// Collapsed storage, diagnostics and usage-total tools. Results are reported
/// through the shared Preferences message.
private struct RebuildAdvancedSection: View {
    @Bindable var state: RebuildPreferencesState
    let connected: [RebuildMicrophoneInputs.Input]
    var timing: RebuildSessionTiming?
    @AppDefault(\.transcriptionHistoryEnabled) private var history
    @AppDefault(\.maxModelStorageGB) private var storageLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(isExpanded: $state.showAdvanced) {
                VStack(alignment: .leading, spacing: 16) {
                    RebuildRecordingTuningView(connected: connected)
                    if let timing { RebuildPerformanceView(timing: timing) }
                    Divider()
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
                            Button("Reset…", role: .destructive) { state.resetUsage = true }
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
                    state.showAdvanced.toggle()
                } label: {
                    HStack {
                        Text("Advanced & support").font(.system(size: 13, weight: .semibold))
                        Text("Input fallbacks, paste behavior, visuals and diagnostics").font(.system(size: 12))
                            .foregroundStyle(RebuildTheme.secondaryText)
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Advanced and support")
                .accessibilityValue(state.showAdvanced ? "Expanded" : "Collapsed")
            }
        }
        .rebuildCard()
        .confirmationDialog("Reset usage totals? Your saved transcripts stay in the library.", isPresented: $state.resetUsage) {
            Button("Reset totals", role: .destructive) { state.effects.resetUsage() }
        }
    }

    private func copyDiagnostics() {
        Task {
            if let text = await state.effects.diagnostics() {
                state.effects.copy(text)
                state.messageTone = .success
                state.message = "Setup diagnostics copied. No transcripts or history are included."
            }
        }
    }

    private func recalculateUsage() {
        Task {
            do { try await state.effects.recalculate() } catch {
                state.messageTone = .error
                state.message = "Usage could not be recalculated: \(error.localizedDescription)"
            }
        }
    }
}
