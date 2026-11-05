import SwiftUI
import XCTest
@testable import AudioWhisper

/// Baselines for the UI that actually ships: the Rebuild workspace pages, the
/// recorder overlay in each state a user sees, and the Aurora waveforms.
///
/// Run with `SNAPSHOT_TESTS=1` (compare) or `SNAPSHOT_RECORD=1` (re-record),
/// locally only — see `SnapshotTestCase` for why CI cannot render these.
@MainActor
final class RebuildSnapshotTests: SnapshotTestCase {
    private var session: RebuildSession!
    private let recorder = AudioEngineRecorder()
    private let page = CGSize(width: 790, height: 720)
    private let hud = RebuildRecorderView.size(preview: false)

    override func setUpWithError() throws {
        try super.setUpWithError()
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.liveTranscriptionPreview = false
        AppDefaults.pressAndHoldEnabled = false
        AppDefaults.transcriptionHistoryEnabled = false
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        AppDefaults.waveformStyle = .classic
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in })
        services.capturePasteDestination = { nil }
        session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
    }

    override func tearDownWithError() throws {
        session?.cancel()
        session = nil
        try super.tearDownWithError()
    }

    private func onCanvas(_ view: some View) -> some View {
        view.background(RebuildTheme.canvas)
    }

    // MARK: - Workspace pages

    func testRecordPageReady() {
        for scheme in [ColorScheme.light, .dark] {
            assertSnapshot(onCanvas(RebuildRecordView(session: session, recorder: recorder, importAudio: {})),
                           named: "Rebuild-record-ready-\(scheme)", size: page, colorScheme: scheme)
        }
    }

    func testSetupPageWithMicrophoneAccessNeeded() {
        session.readiness = RebuildReadiness(
            microphoneGranted: false, modelInstalled: true, runtimeReady: true, checking: false)
        assertSnapshot(onCanvas(RebuildModelsView(session: session)),
                       named: "Rebuild-setup-microphone-needed", size: page)
    }

    func testPreferencesPage() {
        assertSnapshot(onCanvas(RebuildPreferencesView(session: session)),
                       named: "Rebuild-preferences", size: CGSize(width: 790, height: 860))
    }

    func testLibraryWithHistoryOff() {
        assertSnapshot(onCanvas(RebuildLibraryView(history: MockDataManager())),
                       named: "Rebuild-library-off", size: CGSize(width: 790, height: 500))
    }

    // MARK: - Recorder overlay

    func testRecorderWhileRecording() {
        session.toggleRecording()
        // The classic bars take a random jitter each frame, so allow a sliver.
        assertSnapshot(RebuildRecorderView(session: session, recorder: recorder),
                       named: "Rebuild-recorder-recording", size: hud, colorScheme: .dark, tolerance: 0.03)
    }

    func testRecorderExplainsAFailure() {
        session.recorderOutcome = .failed(
            "The microphone recorded only silence. Check the selected microphone, its mute switch and input level.")
        assertSnapshot(RebuildRecorderView(session: session, recorder: recorder),
                       named: "Rebuild-recorder-failed", size: hud, colorScheme: .dark)
    }

    func testRecorderAsksForAManualPaste() {
        session.recorderOutcome = .pasteManually
        assertSnapshot(RebuildRecorderView(session: session, recorder: recorder),
                       named: "Rebuild-recorder-paste-manually", size: hud, colorScheme: .dark)
    }

    // MARK: - Aurora

    func testAuroraStylesAndShapes() {
        let cases: [(name: String, look: (palette: AuroraPalette, shape: AuroraShape))] = [
            ("neon-dusk-horizon", (.neonDusk, .horizon)), ("molten-horizon", (.molten, .horizon)),
            ("electric-horizon", (.electric, .horizon)), ("neon-dusk-lens", (.neonDusk, .lens))
        ]
        for (name, (palette, shape)) in cases {
            let engine = AuroraEngine()
            var time = 0.0
            while time < 1.5 {
                let samples = (0..<64).map { Float(sin(Double($0) * 0.19 + time * 9) * 0.65) * 0.7 }
                engine.advance(to: time, rawLevel: 0.7, samples: samples, reduceMotion: false)
                time += 1.0 / 60
            }
            let view = Canvas { context, size in
                AuroraRenderer.draw(shape, palette: palette, engine: engine, in: &context, size: size)
            }
            .background(RebuildTheme.hudWaveformBackground)
            assertSnapshot(view, named: "Aurora-\(name)", size: CGSize(width: 348, height: 70), colorScheme: .dark)
        }
    }
}
