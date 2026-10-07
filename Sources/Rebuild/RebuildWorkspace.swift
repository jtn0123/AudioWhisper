import AppKit
import KeyboardShortcuts
import SwiftUI

enum RebuildTheme {
    static let accent = Color(red: 0.70, green: 0.27, blue: 0.16)
    static let paper = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.12, alpha: 1)
                : NSColor(red: 0.97, green: 0.96, blue: 0.93, alpha: 1)
        })
    static let ink = Color(red: 0.12, green: 0.14, blue: 0.14)
}

struct RebuildRootView: View {
    @Bindable var session: RebuildSession
    @Bindable var navigation: RebuildNavigation
    @ObservedObject var recorder: AudioEngineRecorder
    let importAudio: () -> Void
    @AppStorage("rebuild.appearance", store: AppDefaults.defaults) private var appearance = "system"

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 218)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(navigation.selection.title.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2)
                    Spacer()
                    Label("On your Mac", systemImage: "lock.shield")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.horizontal, 36).padding(.vertical, 22)
                Divider()
                Group {
                    switch navigation.selection {
                    case .record:
                        RebuildRecordView(
                            session: session, recorder: recorder, importAudio: importAudio,
                            configureShortcut: { navigation.selection = .preferences })
                    case .library: RebuildLibraryView()
                    case .models: RebuildModelsView(session: session)
                    case .writing: RebuildWritingView(session: session)
                    case .preferences: RebuildPreferencesView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.background(RebuildTheme.paper)
        }
        .tint(RebuildTheme.accent)
        .preferredColorScheme(appearance == "dark" ? .dark : appearance == "light" ? .light : nil)
        .onExitCommand { if session.phase.isBusy { session.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await session.refreshSetup() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "waveform.circle.fill").font(.system(size: 32)).foregroundStyle(
                    Color(red: 0.94, green: 0.60, blue: 0.44))
                Text("Audio\nWhisper").font(.system(size: 30, weight: .medium, design: .serif)).lineSpacing(-2)
                Text("PRIVATE DICTATION").font(.system(size: 9, design: .monospaced)).tracking(1.5).foregroundStyle(
                    .white.opacity(0.5))
            }.padding(.bottom, 12)
            VStack(spacing: 7) {
                ForEach(RebuildPage.allCases) { page in
                    Button {
                        navigation.selection = page
                    } label: {
                        Label(page.title, systemImage: page.symbol)
                            .font(.system(size: 13, weight: navigation.selection == page ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(
                                .vertical, 11
                            )
                            .background(
                                navigation.selection == page ? Color.white.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityAddTraits(navigation.selection == page ? .isSelected : [])
                }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Circle().fill(session.readiness.ready ? Color.green.opacity(0.8) : Color.orange).frame(
                        width: 6, height: 6)
                    Text(session.readiness.nextStep).font(.system(size: 11))
                }
                Text("Private by default.\nNo cloud transcription.").font(.system(size: 11)).foregroundStyle(
                    .white.opacity(0.5)
                ).lineSpacing(4)
            }
        }.padding(24).foregroundStyle(.white).background(RebuildTheme.ink)
    }
}

struct RebuildPageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 32, weight: .medium, design: .serif))
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(
                horizontal: false, vertical: true)
        }.padding(.bottom, 20)
    }
}

struct RebuildSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.07)))
    }
}

struct RebuildRecordView: View {
    @Bindable var session: RebuildSession
    @ObservedObject var recorder: AudioEngineRecorder
    let importAudio: () -> Void
    var configureShortcut: () -> Void = {}
    @AppStorage("rebuild.shortcutEnabled", store: AppDefaults.defaults) private var shortcutEnabled = false
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .rebuildRecording)?.description

    private var shortcutHint: String {
        guard shortcutEnabled else {
            return session.phase == .recording
                ? "Click stop to finish. Recording shortcut is off."
                : "Recording shortcut is off. Click the microphone or set up your shortcut."
        }
        guard let shortcut else { return "No recording shortcut assigned. Choose your keys in Preferences." }
        return session.phase == .recording
            ? "Press \(shortcut) or click stop to finish recording."
            : "Press \(shortcut) or click the microphone to record."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RebuildPageHeading(
                    title: session.phase.title, subtitle: "Speak naturally. Get useful text, right where you need it.")
                if !session.readiness.ready && !session.phase.isBusy {
                    HStack(spacing: 16) {
                        Image(systemName: "checklist").font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("One setup, then you’re ready.").font(.headline)
                            Text(session.readiness.nextStep).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Finish setup", action: session.openSetup).buttonStyle(.borderedProminent)
                    }.padding(20).background(RebuildTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                RebuildSection(title: "RECORDING WORKSPACE") {
                    HStack(alignment: .center, spacing: 22) {
                        Button(action: session.toggleRecording) {
                            Image(systemName: session.phase == .recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 28)).frame(width: 74, height: 74)
                                .background(RebuildTheme.accent, in: Circle()).foregroundStyle(.white)
                        }.buttonStyle(.plain).disabled(!session.canToggleRecording)
                            .accessibilityLabel(session.recordingActionTitle)
                            .help(session.recordingBlockedReason ?? session.recordingActionTitle)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(
                                session.phase == .recording
                                    ? "Listening to your microphone"
                                    : session.phase == .starting
                                        ? "Connecting your microphone"
                                    : session.phase == .transcribing
                                        ? "Transcribing your audio" : session.readiness.nextStep
                            ).font(.headline)
                            Text(
                                session.phase == .starting
                                    ? "You can cancel while the microphone connects."
                                    : session.phase == .transcribing
                                    ? "You can cancel while the local model works."
                                    : shortcutHint
                            )
                            .font(.subheadline).foregroundStyle(.secondary)
                            Button("Configure shortcut", action: configureShortcut).buttonStyle(.link).font(.caption)
                            if session.phase == .recording {
                                ProgressView(value: Double(recorder.audioLevel)).frame(width: 220)
                                    .accessibilityLabel("Microphone level")
                            }
                        }
                        Spacer()
                        if session.phase.isBusy {
                            Button("Cancel", action: session.cancel).keyboardShortcut(.escape, modifiers: [])
                        }
                    }.padding(.vertical, 12)
                    Divider()
                    HStack {
                        Label(
                            AppDefaults.transcriptionProvider == .parakeet
                                ? "Parakeet · on device" : "Whisper · on device", systemImage: "cpu")
                        Spacer()
                        Button("Transcribe a file…", action: importAudio).disabled(!session.canImportAudio)
                            .help(session.fileBlockedReason ?? "Choose one audio file to transcribe")
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Text("You can also drop one audio file here. File transcription does not need microphone access.")
                    .font(.caption).foregroundStyle(.secondary)
                if let reason = session.fileBlockedReason {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                }
                if let notice = session.notice {
                    Label(notice, systemImage: session.phase == .failed ? "exclamationmark.triangle" : "info.circle")
                        .font(.subheadline).foregroundStyle(session.phase == .failed ? Color.red : Color.secondary)
                        .textSelection(.enabled)
                    if session.hasRetryAudio {
                        Button("Retry transcription", action: session.retry).disabled(!session.canRetry)
                        if let reason = session.retryBlockedReason {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                RebuildSection(title: "YOUR TRANSCRIPT") {
                    if session.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("A little less typing.").font(.system(size: 25, design: .serif)).foregroundStyle(
                                .secondary)
                            Text(
                                "Your next recording appears here. It is copied when transcription finishes; "
                                    + "saving to your library is optional."
                            )
                            .font(.subheadline).foregroundStyle(.secondary)
                        }.frame(minHeight: 145, alignment: .topLeading)
                    } else {
                        TextEditor(text: $session.transcript).font(.system(size: 15)).scrollContentBackground(.hidden)
                            .frame(minHeight: 145)
                            .accessibilityLabel("Your transcript")
                        HStack {
                            Text("\(UsageMetricsStore.estimatedWordCount(for: session.transcript)) words").font(
                                .caption
                            ).foregroundStyle(.secondary)
                            Spacer()
                            if session.canUseOriginal {
                                Button("Use original", action: session.useOriginalTranscript)
                                    .help("Restore and copy your words before writing cleanup")
                            }
                            Button("Copy text") { PasteManager.copyToClipboard(session.transcript) }
                        }
                        if let original = session.originalTranscript, original != session.transcript {
                            DisclosureGroup("Compare with original") {
                                Text(original).font(.system(size: 15)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }.disabled(session.phase.isBusy)
                        }
                    }
                }
                RebuildUsageView()
            }.padding(36).frame(maxWidth: 950, alignment: .leading)
        }
        .onReceive(NotificationCenter.default.publisher(for: .rebuildSettingsChanged)) { _ in
            shortcut = KeyboardShortcuts.getShortcut(for: .rebuildRecording)?.description
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard urls.count == 1, let url = urls.first, session.canImportAudio else { return false }
            session.importAudio(url)
            return true
        }
    }
}

struct RebuildRecorderView: View {
    @Bindable var session: RebuildSession
    @ObservedObject var recorder: AudioEngineRecorder
    var body: some View {
        VStack(spacing: 12) {
            WaveformContainer(
                status: session.phase == .recording ? .recording : .processing("Transcribing"),
                audioLevel: recorder.audioLevel, waveformSamples: recorder.waveformSamples,
                frequencyBands: recorder.frequencyBands, onTap: session.toggleRecording
            ).frame(height: 145)
            HStack {
                Button("Cancel", action: session.cancel)
                Spacer()
                Button(session.phase == .recording ? "Finish" : "Transcribing…", action: session.finishRecording)
                    .buttonStyle(.borderedProminent).disabled(session.phase != .recording)
            }.padding(.horizontal, 18)
        }.padding(.vertical, 14).frame(width: 380, height: 230)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .onExitCommand(perform: session.cancel)
    }
}

struct RebuildUsageView: View {
    var body: some View {
        HStack(spacing: 36) {
            metric("Sessions", value: "\(UsageMetricsStore.shared.snapshot.totalSessions)")
            metric("Words spoken", value: "\(UsageMetricsStore.shared.snapshot.totalWords)")
            metric(
                "Estimated time saved", value: "\(Int(UsageMetricsStore.shared.snapshot.estimatedTimeSaved / 60)) min")
            Spacer()
        }.padding(.vertical, 12)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 23, weight: .medium, design: .serif))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}
