import AppKit
import SwiftUI
import XCTest
@testable import AudioWhisper

@MainActor
final class DictationFlowVisualTests: IsolatedXCTestCase {
    func testCaptureDailyDictationViews() async throws {
        guard let directory = ProcessInfo.processInfo.environment["DICTATION_CAPTURE_DIR"] else {
            throw XCTSkip("Opt in to native daily-dictation view captures")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        AppDefaults.playCompletionSound = false
        AppDefaults.enableSmartPaste = false
        AppDefaults.semanticCorrectionMode = .off
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.customVocabulary = ""
        AppDefaults.defaults.removeObject(forKey: "rebuild.practiceCompleted")
        let preview = RebuildLivePreview(interval: .milliseconds(1)) { _, _ in
            "The quick brown fox jumps over the lazy dog while I keep speaking."
        }
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { URL(fileURLWithPath: "/visual-fixture.wav") }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "I work with post gress.", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in })
        services.capturePasteDestination = { nil }
        services.previewSnapshot = {
            RecordingPreviewSnapshot(samples: [Float](repeating: 0.1, count: 16000), sampleRate: 16000)
        }
        let session = RebuildSession(services: services, livePreview: preview)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        for scheme in [ColorScheme.light, .dark] {
            let name = scheme == .light ? "light" : "dark"
            try capture(RebuildWritingView(session: session), "writing-\(name)", NSSize(width: 790, height: 860), scheme, output)
            try capture(RebuildPracticeView(session: session), "practice-ready-\(name)",
                        NSSize(width: 730, height: 200), scheme, output)
        }
        AppDefaults.customVocabulary = "AudioWhisper\nKubernetes\npost gress -> Postgres"
        try capture(RebuildWritingRulesCard(), "vocabulary", NSSize(width: 730, height: 550), .light, output)
        session.startPractice()
        session.finishRecording()
        try await requireVisualState("Completed practice recording") { session.phase == .completed }
        try capture(RebuildPracticeView(session: session), "practice-result", NSSize(width: 730, height: 330), .light, output)
        session.transcript = "I work with Postgres."
        try capture(RebuildTranscriptCard(session: session), "transcript-correction",
                    NSSize(width: 730, height: 330), .light, output)
        try capture(RebuildRememberCorrectionView(draft: RebuildVocabularyDocument.correction(
            from: session.deliveredTranscript, to: session.transcript)), "remember-correction",
            NSSize(width: 488, height: 300), .light, output)
        session.cancel()
        AppDefaults.liveTranscriptionPreview = true
        session.toggleRecording()
        try await requireVisualState("Stable live preview") { !preview.stablePrefix.isEmpty }
        try capture(RebuildRecorderView(session: session, recorder: AudioEngineRecorder()), "preview",
                    NSSize(width: 380, height: 350), .dark, output)
        session.cancel()
    }

    private func capture(
        _ view: some View, _ name: String, _ size: NSSize, _ scheme: ColorScheme, _ output: URL
    ) throws {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).background(RebuildTheme.canvas))
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
