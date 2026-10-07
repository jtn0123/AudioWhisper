import AppKit
import KeyboardShortcuts
import SwiftUI

@MainActor
enum RebuildWorkspaceHosting {
    static func controller(for view: RebuildRootView) -> NSHostingController<RebuildRootView> {
        let controller = NSHostingController(rootView: view)
        // The native resizable window owns its bounds. A page's fitting size
        // must not become the window's minimum or stretch it below the screen.
        controller.sizingOptions = []
        return controller
    }
}

extension RebuildPage {
    var subtitle: String {
        switch self {
        case .record: return "Speak naturally. Your text is copied when transcription finishes."
        case .library: return "Saved transcripts stay on this Mac. Saving is optional."
        case .models: return "Two essentials: microphone access and a voice model."
        case .writing: return "Optional on-device grammar cleanup. Your original words are kept."
        case .preferences: return "Shortcuts, delivery, privacy and appearance."
        }
    }
}

struct RebuildRootView: View {
    @Bindable var session: RebuildSession
    @Bindable var navigation: RebuildNavigation
    @ObservedObject var recorder: AudioEngineRecorder
    let importAudio: () -> Void
    var history: DataManagerProtocol = DataManager.shared
    var readShortcut: @MainActor () -> String? = {
        KeyboardShortcuts.getShortcut(for: .rebuildRecording)?.description
    }
    @AppStorage("rebuild.appearance", store: AppDefaults.defaults) private var appearance = "system"

    var body: some View {
        HStack(spacing: 0) {
            RebuildSidebar(session: session, navigation: navigation)
            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(RebuildTheme.border).frame(height: 1).accessibilityHidden(true)
                page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.background(RebuildTheme.canvas)
        }
        .tint(RebuildTheme.accent)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .onExitCommand { if session.phase.isBusy { session.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await session.refreshSetup() }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.selection.title).font(RebuildTheme.titleFont(20))
                    .accessibilityAddTraits(.isHeader)
                Text(navigation.selection.subtitle).font(.system(size: 12))
                    .foregroundStyle(RebuildTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Label {
                Text("On your Mac").foregroundStyle(RebuildTheme.secondaryText)
            } icon: {
                Image(systemName: "lock.shield").foregroundStyle(RebuildTheme.accentText)
            }
            .font(.system(size: 11, weight: .medium))
            .help("Transcription, writing cleanup and your library stay on this Mac.")
        }
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 12)
    }

    @ViewBuilder private var page: some View {
        switch navigation.selection {
        case .record:
            RebuildRecordView(
                session: session, recorder: recorder, importAudio: importAudio,
                configureShortcut: { navigation.selection = .preferences }, readShortcut: readShortcut)
        case .library: RebuildLibraryView(history: history)
        case .models: RebuildModelsView(session: session)
        case .writing: RebuildWritingView(session: session)
        case .preferences: RebuildPreferencesView(session: session)
        }
    }
}

/// Slate sidebar: compact brand, page navigation (⌘1–⌘5) and live status.
struct RebuildSidebar: View {
    @Bindable var session: RebuildSession
    @Bindable var navigation: RebuildNavigation
    @FocusState private var focusedPage: RebuildPage?
    @State private var hoveredPage: RebuildPage?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand.padding(.bottom, 22)
            VStack(spacing: 2) {
                ForEach(Array(RebuildPage.allCases.enumerated()), id: \.element) { index, page in
                    navButton(page, number: index + 1)
                }
            }
            Spacer(minLength: 16)
            status
        }
        .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 16)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .foregroundStyle(.white)
        .background(RebuildTheme.sidebarBackground)
        .overlay(alignment: .trailing) { Rectangle().fill(RebuildTheme.sidebarDivider).frame(width: 1) }
        .environment(\.colorScheme, .dark)
        // Clicks, ⌘1–⌘5 and in-page links all change the selection; keyboard
        // focus follows it so the ring never stays on a page left behind.
        // Tab and arrow keys still move focus without selecting.
        .onChange(of: navigation.selection) { _, page in focusedPage = page }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 24))
                .foregroundStyle(RebuildTheme.sidebarAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("AudioWhisper").font(RebuildTheme.brandFont(17))
                Text("PRIVATE DICTATION").font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .tracking(1.2).foregroundStyle(RebuildTheme.sidebarSecondary)
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AudioWhisper, private dictation")
    }

    private func navButton(_ page: RebuildPage, number: Int) -> some View {
        let selected = navigation.selection == page
        return Button {
            navigation.selection = page
            focusedPage = page
        } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).font(.system(size: 13, weight: .medium)).frame(width: 18)
                    .foregroundStyle(selected ? RebuildTheme.sidebarAccent : RebuildTheme.sidebarIcon)
                Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .white.opacity(0.86))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(navFill(page, selected: selected), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                // Increase Contrast outlines the selection; the focus ring
                // always wins so keyboard position is never ambiguous.
                let focused = focusedPage == page
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        focused ? RebuildTheme.sidebarAccent : .white.opacity(0.5), lineWidth: focused ? 1.5 : 1)
                    .opacity(focused || (selected && contrast == .increased) ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredPage = $0 ? page : (hoveredPage == page ? nil : hoveredPage) }
        .focused($focusedPage, equals: page)
        .focusEffectDisabled()
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
        .help("\(page.title) (⌘\(number))")
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func navFill(_ page: RebuildPage, selected: Bool) -> Color {
        if selected { return RebuildTheme.sidebarSelection }
        return hoveredPage == page ? RebuildTheme.sidebarHover : .clear
    }

    private var setupBusy: Bool { session.isInstalling || session.maintenanceInProgress }

    private var statusLine: (text: String, color: Color) {
        switch session.phase {
        case .starting: return ("Connecting microphone…", RebuildTheme.warning)
        case .recording: return ("Recording", RebuildTheme.recording)
        case .transcribing: return ("Transcribing…", RebuildTheme.warning)
        default:
            if setupBusy { return ("Model setup in progress…", RebuildTheme.warning) }
            return (
                session.readiness.nextStep, session.readiness.ready ? RebuildTheme.success : RebuildTheme.warning
            )
        }
    }

    private var status: some View {
        let line = statusLine
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                navigation.selection = .models
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(line.color).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0.height }
                    Text(line.text).font(.system(size: 11.5, weight: .medium)).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Models & setup")
            .accessibilityLabel("Status: \(line.text)")
            .accessibilityHint("Opens Models & setup")
            Text("On-device. No cloud transcription.").font(.system(size: 11))
                .foregroundStyle(RebuildTheme.sidebarSecondary)
        }.padding(.horizontal, 8)
    }
}

struct RebuildRecordView: View {
    @Bindable var session: RebuildSession
    @ObservedObject var recorder: AudioEngineRecorder
    let importAudio: () -> Void
    var configureShortcut: () -> Void = {}
    private let readShortcut: @MainActor () -> String?
    @AppStorage("rebuild.shortcutEnabled", store: AppDefaults.defaults) private var shortcutEnabled = false
    @State private var shortcut: String?
    @State private var dropTargeted = false

    init(
        session: RebuildSession, recorder: AudioEngineRecorder, importAudio: @escaping () -> Void,
        configureShortcut: @escaping () -> Void = {},
        readShortcut: @escaping @MainActor () -> String? = {
            KeyboardShortcuts.getShortcut(for: .rebuildRecording)?.description
        }
    ) {
        self.session = session
        self.recorder = recorder
        self.importAudio = importAudio
        self.configureShortcut = configureShortcut
        self.readShortcut = readShortcut
        self._shortcut = State(initialValue: readShortcut())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                setupBanner
                recorderCard
                notice
                RebuildTranscriptCard(session: session)
                RebuildUsageView()
            }
            .padding(.horizontal, 28).padding(.vertical, 20).frame(maxWidth: 860, alignment: .leading)
        }
        .overlay { if dropTargeted { dropOverlay } }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildSettingsChanged)) { _ in
            shortcut = readShortcut()
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, session.canImportAudio else { return false }
            session.importAudio(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var setupBusy: Bool { session.isInstalling || session.maintenanceInProgress }

    // MARK: Setup and notices

    @ViewBuilder private var setupBanner: some View {
        if !session.readiness.ready && !session.readiness.checking && !session.phase.isBusy {
            RebuildCallout(
                tone: setupBusy ? .info : .warning,
                message: setupBusy ? "Model setup in progress" : session.readiness.nextStep,
                detail: setupBusy
                    ? "Recording becomes available when setup finishes."
                    : "Recording needs microphone access and an installed voice model."
            ) {
                Button("Open setup", action: session.openSetup).buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder private var notice: some View {
        if let notice = session.notice {
            RebuildCallout(
                tone: session.phase == .failed ? .error : .info, message: notice,
                detail: session.hasRetryAudio ? session.retryBlockedReason : nil
            ) {
                if session.hasRetryAudio {
                    Button("Retry transcription", action: session.retry).disabled(!session.canRetry)
                }
            }
        }
    }

    // MARK: Recorder

    private var recorderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                recordButton
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(statusTitle).font(.system(size: 17, weight: .semibold))
                        if let start = session.recordingStartedAt {
                            RebuildElapsedTime(start: start)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(RebuildTheme.recordingText)
                        }
                    }
                    statusDetail
                    if session.phase == .recording {
                        ProgressView(value: Double(recorder.audioLevel)).frame(maxWidth: 220)
                            .accessibilityLabel("Microphone level")
                    }
                }
                Spacer(minLength: 12)
                trailingAction
            }
            Divider()
            HStack(spacing: 12) {
                Label(engineSummary, systemImage: "cpu")
                Spacer(minLength: 8)
                Text(session.fileBlockedReason ?? "Or drop one audio file here. No microphone needed.")
                    .lineLimit(1).truncationMode(.tail)
            }.font(.system(size: 11.5)).foregroundStyle(RebuildTheme.secondaryText)
        }.rebuildCard(padding: 18)
    }

    private var recordButton: some View {
        Button(action: session.toggleRecording) {
            ZStack {
                Circle().fill(recordFill)
                if session.phase == .starting || session.phase == .transcribing {
                    ProgressView().controlSize(.small).environment(\.colorScheme, .dark)
                } else {
                    Image(systemName: session.phase == .recording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(.white)
                }
            }
            .frame(width: 64, height: 64)
            .overlay {
                if session.phase == .recording {
                    Circle().strokeBorder(RebuildTheme.recording.opacity(0.3), lineWidth: 4).padding(-7)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!session.canToggleRecording)
        .accessibilityLabel(session.recordingActionTitle)
        .help(session.recordingBlockedReason ?? session.recordingActionTitle)
    }

    private var recordFill: Color {
        switch session.phase {
        case .recording: return RebuildTheme.recording
        // Solid slate keeps the white glyph legible in both appearances.
        case .starting, .transcribing: return RebuildTheme.inactiveFill
        default: return session.readiness.ready && !setupBusy ? RebuildTheme.accent : RebuildTheme.inactiveFill
        }
    }

    private var statusTitle: String {
        switch session.phase {
        case .starting: return "Connecting microphone…"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing…"
        case .completed: return "Copied to your clipboard"
        case .failed: return "Let’s try that again"
        case .idle:
            if setupBusy { return "Model setup in progress" }
            return session.readiness.ready ? "Ready to record" : session.readiness.nextStep
        }
    }

    @ViewBuilder private var statusDetail: some View {
        switch session.phase {
        case .starting:
            Text("You can cancel while the microphone connects.").font(.system(size: 12.5))
                .foregroundStyle(RebuildTheme.secondaryText)
        case .transcribing:
            Text("The local model is working. You can cancel.").font(.system(size: 12.5))
                .foregroundStyle(RebuildTheme.secondaryText)
        default:
            shortcutLine
        }
    }

    private var shortcutLine: some View {
        let recording = session.phase == .recording
        let assigned = shortcutEnabled ? shortcut : nil
        return HStack(spacing: 6) {
            if let assigned {
                Text("Press")
                RebuildKeycap(keys: assigned)
                Text(recording ? "or click stop to finish." : "from any app to start.")
            } else {
                Text(shortcutEnabled ? "No recording shortcut assigned." : "Recording shortcut is off.")
            }
            Button(assigned == nil ? "Set up" : "Change", action: configureShortcut)
                .buttonStyle(.rebuildLink)
                .fontWeight(.medium)
                .accessibilityLabel(assigned == nil ? "Set up recording shortcut" : "Change recording shortcut")
        }
        .font(.system(size: 12.5)).foregroundStyle(RebuildTheme.secondaryText)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var trailingAction: some View {
        if session.phase.isBusy {
            Button("Cancel", action: session.cancel)
                .keyboardShortcut(.escape, modifiers: [])
                .controlSize(.large)
                .help("Cancel (Esc). Nothing is copied or saved.")
        } else {
            Button("Transcribe a file…", action: importAudio)
                .controlSize(.large)
                .disabled(!session.canImportAudio)
                .help(session.fileBlockedReason ?? "Choose one audio file to transcribe")
        }
    }

    private var engineSummary: String {
        switch AppDefaults.transcriptionProvider {
        case .parakeet: return "Parakeet \(Self.shortName(AppDefaults.selectedParakeetModel.displayName)) · on device"
        case .local: return "Whisper \(Self.shortName(AppDefaults.selectedWhisperModel.displayName)) · on device"
        }
    }

    static func shortName(_ name: String) -> String { name.components(separatedBy: " (").first ?? name }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(RebuildTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(RebuildTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                Label(
                    session.fileBlockedReason ?? "Drop one audio file to transcribe it",
                    systemImage: session.canImportAudio ? "waveform.badge.plus" : "nosign"
                ).font(.system(size: 14, weight: .medium)).padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(12)
            .allowsHitTesting(false)
    }
}

/// The latest transcript, editable, with copy and original-text recovery.
struct RebuildTranscriptCard: View {
    @Bindable var session: RebuildSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Transcript").font(.system(size: 13, weight: .semibold)).accessibilityAddTraits(.isHeader)
                if !session.transcript.isEmpty {
                    Text("\(UsageMetricsStore.estimatedWordCount(for: session.transcript)) words")
                        .font(.system(size: 12)).foregroundStyle(RebuildTheme.secondaryText)
                }
                Spacer()
                if !session.transcript.isEmpty {
                    if session.canUseOriginal {
                        Button("Use original", action: session.useOriginalTranscript)
                            .help("Restore and copy your words before writing cleanup")
                    }
                    Button("Copy text") { PasteManager.copyToClipboard(session.transcript) }
                }
            }
            if session.transcript.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little less typing.").font(RebuildTheme.titleFont(15))
                    Text("Your next transcript appears here and is copied automatically. Saving to the library is optional.")
                        .font(.system(size: 12.5)).foregroundStyle(RebuildTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            } else {
                TextEditor(text: $session.transcript).font(.system(size: 14)).scrollContentBackground(.hidden)
                    .frame(minHeight: 110, maxHeight: 240)
                    .accessibilityLabel("Your transcript")
                if let original = session.originalTranscript, original != session.transcript {
                    DisclosureGroup("Compare with original") {
                        Text(original).font(.system(size: 14)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }.disabled(session.phase.isBusy)
                }
            }
        }.rebuildCard()
    }
}

/// The floating recording HUD. Its 380×230 frame is relied on by the desktop
/// acceptance harness, which clicks Cancel near the bottom-left corner.
struct RebuildRecorderView: View {
    @Bindable var session: RebuildSession
    @ObservedObject var recorder: AudioEngineRecorder

    var body: some View {
        VStack(spacing: 0) {
            WaveformContainer(
                status: session.phase == .recording ? .recording : .processing("Transcribing"),
                audioLevel: recorder.audioLevel, waveformSamples: recorder.waveformSamples,
                frequencyBands: recorder.frequencyBands, showsStatusRow: false,
                showsGlassBackground: false, backgroundColor: RebuildTheme.hudWaveformBackground,
                waveformColor: RebuildTheme.hudWaveformForeground, onTap: session.toggleRecording
            )
            .frame(height: 118)
            // Keep the waveform's own drop shadow and coral glow inside its
            // panel so the HUD stays one calm slate surface.
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.06)))
            .padding(.horizontal, 12).padding(.top, 12)
            statusRow.frame(height: 40).padding(.horizontal, 18)
            Spacer(minLength: 0)
            controls.frame(height: 32).padding(.horizontal, 18).padding(.bottom, 18)
        }
        .frame(width: 380, height: 230)
        .background(RebuildTheme.hudBackground.opacity(0.97), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(RebuildTheme.hudBorder))
        .environment(\.colorScheme, .dark)
        .tint(RebuildTheme.hudAccent)
        .onExitCommand(perform: session.cancel)
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(session.phase == .recording ? RebuildTheme.recording : RebuildTheme.warning)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(session.phase == .recording ? "Recording" : "Transcribing…")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            if let start = session.recordingStartedAt {
                RebuildElapsedTime(start: start)
                    .font(.system(size: 24, weight: .medium)).foregroundStyle(.white)
            } else if session.phase == .transcribing {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var controls: some View {
        HStack {
            Button(action: session.cancel) {
                Text("Cancel").frame(minWidth: 84)
            }
            .buttonStyle(RebuildHUDButtonStyle())
            .help("Discard this recording. Nothing is copied or saved.")
            Spacer()
            Button(action: session.finishRecording) {
                Label(session.phase == .recording ? "Stop & transcribe" : "Transcribing…", systemImage: "stop.fill")
                    .frame(minWidth: 140)
            }
            .buttonStyle(RebuildHUDButtonStyle(prominent: true))
            .disabled(session.phase != .recording)
        }
    }
}

struct RebuildUsageView: View {
    var body: some View {
        let snapshot = UsageMetricsStore.shared.snapshot
        HStack(spacing: 18) {
            metric(snapshot.totalSessions.formatted(), "sessions")
            metric(snapshot.totalWords.formatted(), "words spoken")
            metric("\(Int(snapshot.estimatedTimeSaved / 60))", "min saved (est.)")
            Spacer()
        }
        .font(.system(size: 12))
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ value: String, _ title: String) -> Text {
        Text(value).fontWeight(.semibold) + Text(" \(title)").foregroundStyle(RebuildTheme.secondaryText)
    }
}
