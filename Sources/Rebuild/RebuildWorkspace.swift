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
    @AppStorage("rebuild.appearance", store: AppDefaults.defaults) private var appearance = "system"

    var body: some View {
        HStack(spacing: 0) {
            RebuildSidebar(session: session, navigation: navigation)
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.background(RebuildTheme.paper)
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
                Text(navigation.selection.title).font(RebuildTheme.titleFont(22))
                    .accessibilityAddTraits(.isHeader)
                Text(navigation.selection.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Label("On your Mac", systemImage: "lock.shield").font(.system(size: 11)).foregroundStyle(.secondary)
                .help("Transcription, writing cleanup and your library stay on this Mac.")
        }
        .padding(.horizontal, 28).padding(.top, 14).padding(.bottom, 12)
    }

    @ViewBuilder private var page: some View {
        switch navigation.selection {
        case .record:
            RebuildRecordView(
                session: session, recorder: recorder, importAudio: importAudio,
                configureShortcut: { navigation.selection = .preferences })
        case .library: RebuildLibraryView(history: history)
        case .models: RebuildModelsView(session: session)
        case .writing: RebuildWritingView(session: session)
        case .preferences: RebuildPreferencesView()
        }
    }
}

/// Ink sidebar: compact brand, page navigation (⌘1–⌘5) and live status.
struct RebuildSidebar: View {
    @Bindable var session: RebuildSession
    @Bindable var navigation: RebuildNavigation
    @FocusState private var focusedPage: RebuildPage?

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
        .background(RebuildTheme.ink)
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.07)).frame(width: 1) }
        .environment(\.colorScheme, .dark)
        // Clicks, ⌘1–⌘5 and in-page links all change the selection; keyboard
        // focus follows it so the ring never stays on a page left behind.
        // Tab and arrow keys still move focus without selecting.
        .onChange(of: navigation.selection) { _, page in focusedPage = page }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 24)).foregroundStyle(RebuildTheme.brand)
            VStack(alignment: .leading, spacing: 1) {
                Text("AudioWhisper").font(RebuildTheme.titleFont(17))
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
                    .foregroundStyle(selected ? RebuildTheme.brand : .white.opacity(0.78))
                Text(page.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .white : .white.opacity(0.86))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(selected ? Color.white.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .leading) {
                if selected { Capsule().fill(RebuildTheme.brand).frame(width: 3, height: 14) }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(RebuildTheme.brand, lineWidth: 1.5).opacity(focusedPage == page ? 1 : 0))
        }
        .buttonStyle(.plain)
        .focused($focusedPage, equals: page)
        .focusEffectDisabled()
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: .command)
        .help("\(page.title) (⌘\(number))")
        .accessibilityLabel(page.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var setupBusy: Bool { session.isInstalling || session.maintenanceInProgress }

    private var statusLine: (text: String, color: Color) {
        switch session.phase {
        case .starting: return ("Connecting microphone…", .orange)
        case .recording: return ("Recording", .red)
        case .transcribing: return ("Transcribing…", .orange)
        default:
            if setupBusy { return ("Model setup in progress…", .orange) }
            return (session.readiness.nextStep, session.readiness.ready ? .green : .orange)
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
    @AppStorage("rebuild.shortcutEnabled", store: AppDefaults.defaults) private var shortcutEnabled = false
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .rebuildRecording)?.description
    @State private var dropTargeted = false

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
            shortcut = KeyboardShortcuts.getShortcut(for: .rebuildRecording)?.description
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
                                .font(.system(size: 17, weight: .medium, design: .monospaced))
                                .foregroundStyle(.red)
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
            }.font(.system(size: 11.5)).foregroundStyle(.secondary)
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
                    Circle().strokeBorder(Color.red.opacity(0.3), lineWidth: 4).padding(-7)
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
        case .recording: return .red
        // Solid gray keeps the white glyph legible in both appearances.
        case .starting, .transcribing: return Color(nsColor: .systemGray)
        default: return session.readiness.ready && !setupBusy ? RebuildTheme.accent : Color(nsColor: .systemGray)
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
            Text("You can cancel while the microphone connects.").font(.system(size: 12.5)).foregroundStyle(.secondary)
        case .transcribing:
            Text("The local model is working. You can cancel.").font(.system(size: 12.5)).foregroundStyle(.secondary)
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
                .buttonStyle(.link)
                .foregroundStyle(Color(nsColor: .linkColor))
                .accessibilityLabel(assigned == nil ? "Set up recording shortcut" : "Change recording shortcut")
        }
        .font(.system(size: 12.5)).foregroundStyle(.secondary)
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
                        .font(.system(size: 12)).foregroundStyle(.secondary)
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
                    Text("A little less typing.").font(RebuildTheme.titleFont(19)).foregroundStyle(.secondary)
                    Text("Your next transcript appears here and is copied automatically. Saving to the library is optional.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
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
                frequencyBands: recorder.frequencyBands, showsStatusRow: false, onTap: session.toggleRecording
            )
            .frame(height: 118)
            .padding(.horizontal, 12).padding(.top, 12)
            statusRow.frame(height: 40).padding(.horizontal, 18)
            Spacer(minLength: 0)
            controls.frame(height: 32).padding(.horizontal, 18).padding(.bottom, 18)
        }
        .frame(width: 380, height: 230)
        .background(RebuildTheme.ink.opacity(0.97), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.09)))
        .environment(\.colorScheme, .dark)
        .tint(RebuildTheme.accent)
        .onExitCommand(perform: session.cancel)
    }

    private var statusRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(session.phase == .recording ? Color.red : Color.orange).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(session.phase == .recording ? "Recording" : "Transcribing…")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            if let start = session.recordingStartedAt {
                RebuildElapsedTime(start: start)
                    .font(.system(size: 26, weight: .medium, design: .monospaced)).foregroundStyle(.white)
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
            .controlSize(.large)
            .help("Discard this recording. Nothing is copied or saved.")
            Spacer()
            Button(action: session.finishRecording) {
                Label(session.phase == .recording ? "Stop & transcribe" : "Transcribing…", systemImage: "stop.fill")
                    .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
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
        Text(value).fontWeight(.semibold) + Text(" \(title)").foregroundStyle(.secondary)
    }
}
