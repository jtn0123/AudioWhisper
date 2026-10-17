import AppKit
import SwiftUI
import XCTest
@testable import AudioWhisper

/// Opt-in captures of real SwiftUI/AppKit views. No microphone or permissions.
@MainActor
final class RebuildPolishVisualTests: IsolatedXCTestCase {
    func testCapturePolishStates() async throws {
        guard let directory = ProcessInfo.processInfo.environment["POLISH_CAPTURE_DIR"] else {
            throw XCTSkip("Set POLISH_CAPTURE_DIR to capture native views")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.liveTranscriptionPreview = false
        AppDefaults.pressAndHoldEnabled = false
        AppDefaults.transcriptionHistoryEnabled = false
        AppDefaults.enableSmartPaste = false
        AppDefaults.waveformStyle = .classic
        let preview = RebuildLivePreview(interval: .milliseconds(1)) { _, _ in
            "The quick brown fox jumps over the lazy dog."
        }
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in })
        services.capturePasteDestination = { nil }
        services.previewSnapshot = { RecordingPreviewSnapshot(samples: [Float](repeating: 0.1, count: 16000), sampleRate: 16000) }
        let session = RebuildSession(services: services, livePreview: preview)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        let recorder = AudioEngineRecorder()
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            try capture(RebuildPreferencesView(session: session), name: "preferences-\(name)",
                        size: NSSize(width: 790, height: 860), scheme: scheme, output: output)
            try capture(RebuildRecordView(session: session, recorder: recorder, importAudio: {}),
                        name: "record-idle-\(name)", size: NSSize(width: 790, height: 720), scheme: scheme, output: output)
            try capture(RebuildModelsView(session: session), name: "setup-\(name)",
                        size: NSSize(width: 790, height: 720), scheme: scheme, output: output)
            try capture(RebuildWritingView(session: session), name: "writing-\(name)",
                        size: NSSize(width: 790, height: 860), scheme: scheme, output: output)
            try capture(RebuildLibraryView(history: MockDataManager()), name: "library-off-\(name)",
                        size: NSSize(width: 790, height: 500), scheme: scheme, output: output)
        }
        let preferences = RebuildPreferencesState()
        preferences.showAdvanced = true
        try capture(RebuildPreferencesView(session: session, state: preferences), name: "preferences-advanced-light",
                    size: NSSize(width: 790, height: 1500), scheme: .light, output: output)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.toggleRecording()
        defer { session.cancel() }
        try capture(RebuildRecorderView(session: session, recorder: recorder), name: "recorder",
                    size: NSSize(width: 380, height: 230), scheme: .dark, output: output)
        session.cancel()
        AppDefaults.liveTranscriptionPreview = true
        session.toggleRecording()
        try await requireVisualState("Recorder preview text") { !preview.text.isEmpty }
        try capture(RebuildRecorderView(session: session, recorder: recorder), name: "recorder-preview",
                    size: NSSize(width: 380, height: 350), scheme: .dark, output: output)
        session.finishRecording()
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        try capture(RebuildRecordView(session: session, recorder: recorder, importAudio: {}),
                    name: "record-error-dark", size: NSSize(width: 790, height: 720), scheme: .dark, output: output)
        session.cancel()
        session.importAudio(URL(fileURLWithPath: "/fixture.wav"))
        try capture(RebuildRecordView(session: session, recorder: recorder, importAudio: {}),
                    name: "record-processing-light", size: NSSize(width: 790, height: 720), scheme: .light, output: output)
    }

    private func capture(
        _ view: some View, name: String, size: NSSize, scheme: ColorScheme, output: URL
    ) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
            .background(RebuildTheme.canvas))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent("\(name).png"))
    }
}
