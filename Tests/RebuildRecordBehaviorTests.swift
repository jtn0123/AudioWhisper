import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildRecordBehaviorTests: IsolatedXCTestCase {
    private var start: ((UUID) async -> Bool)?
    private var transcribe: (() async throws -> TranscriptionResult)?
    private var copies: [String] = []
    private var saves = 0

    private func makeSession() -> RebuildSession {
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in
                if let transcribe = self.transcribe { return try await transcribe() }
                return TranscriptionResult(text: "Recovered words.", correctionOutcome: nil)
            }, copy: { self.copies.append($0) }, save: { _, _, _ in self.saves += 1 })
        services.startAsync = start
        let session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        return session
    }

    private func view(_ session: RebuildSession, shortcut: String? = nil) -> RebuildRecordView {
        RebuildRecordView(session: session, recorder: AudioEngineRecorder(), importAudio: {},
                          configureShortcut: {}, readShortcut: { shortcut })
    }

    func testConnectingControlsCancelBeforeMicrophoneStartCompletes() async throws {
        var pending: CheckedContinuation<Bool, Never>?
        start = { _ in await withCheckedContinuation { pending = $0 } }
        let session = makeSession()
        session.toggleRecording()
        try await waitFor { pending != nil }
        let view = view(session)
        _ = try view.inspect().find(text: "You can cancel while the microphone connects.")
        let record = try view.inspect().find(ViewType.Button.self, where: {
            (try? $0.accessibilityLabel().string()) == "Connecting microphone…"
        })
        XCTAssertTrue(try record.isDisabled())
        try view.inspect().find(button: "Cancel").tap()
        try XCTUnwrap(pending).resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(copies.isEmpty)
        XCTAssertEqual(saves, 0)
    }

    func testRecordPageShowsTranscribingAndDiscardsACancelledLateResult() async throws {
        var pending: CheckedContinuation<TranscriptionResult, Never>?
        transcribe = { await withCheckedContinuation { pending = $0 } }
        let session = makeSession()
        session.importAudio(URL(fileURLWithPath: "/fixture.wav"))
        try await waitFor { pending != nil }
        let view = view(session)
        _ = try view.inspect().find(text: "The local model is working. You can cancel.")
        XCTAssertThrowsError(try view.inspect().find(button: "Transcribe a file…"))
        try view.inspect().find(button: "Cancel").tap()
        try XCTUnwrap(pending).resume(returning: TranscriptionResult(text: "late", correctionOutcome: nil))
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(copies.isEmpty)
        XCTAssertEqual(saves, 0)
    }

    func testFailureNoticeRetryAndCompletedControlsUseTheCapturedModel() async throws {
        var attempts = 0
        transcribe = {
            attempts += 1
            if attempts == 1 { throw NSError(domain: "fixture", code: 1,
                                             userInfo: [NSLocalizedDescriptionKey: "Fixture inference interrupted"]) }
            return TranscriptionResult(text: "Recovered words.", correctionOutcome: nil)
        }
        let session = makeSession()
        session.importAudio(URL(fileURLWithPath: "/fixture.wav"))
        try await waitFor { session.phase == .failed }
        let view = view(session)
        _ = try view.inspect().find(text: "Let’s try that again")
        _ = try view.inspect().find(text: "Fixture inference interrupted")
        AppDefaults.selectedWhisperModel = .tiny
        XCTAssertTrue(try view.inspect().find(button: "Retry transcription").isDisabled())
        _ = try view.inspect().find(text: "Select the voice model used for this recording before retrying.")
        AppDefaults.selectedWhisperModel = .base
        try view.inspect().find(button: "Retry transcription").tap()
        try await waitFor { session.phase == .completed }
        _ = try view.inspect().find(text: "Copied to your clipboard")
        XCTAssertThrowsError(try view.inspect().find(button: "Retry transcription"))
        XCTAssertEqual(copies, ["Recovered words."])
        XCTAssertEqual(saves, 1)
    }

    func testRecordingAndAssignedShortcutHaveVisibleStopAndChangeControls() throws {
        let session = makeSession()
        AppDefaults.defaults.set(true, forKey: "rebuild.shortcutEnabled")
        session.toggleRecording()
        let view = view(session, shortcut: "⌥⇧⌘R")
        _ = try view.inspect().find(text: "Recording")
        _ = try view.inspect().find(text: "or click stop to finish.")
        _ = try view.inspect().find(button: "Change")
        let record = try view.inspect().find(ViewType.Button.self, where: {
            (try? $0.accessibilityLabel().string()) == "Finish recording"
        })
        XCTAssertFalse(try record.isDisabled())
        try record.tap()
        XCTAssertEqual(session.phase, .failed)
        _ = try view.inspect().find(text: "No audio was captured. Try a different microphone.")
        XCTAssertTrue(copies.isEmpty)
    }

    func testParakeetSummaryAndUnassignedShortcutDoNotClaimAnAssignedKey() throws {
        let session = makeSession()
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.selectedParakeetModel = .v3Multilingual
        AppDefaults.defaults.set(true, forKey: "rebuild.shortcutEnabled")
        let view = view(session)
        _ = try view.inspect().find(text: "No recording shortcut assigned.")
        _ = try view.inspect().find(button: "Set up")
        let summary = try view.inspect().find(ViewType.Label.self, where: {
            (try? $0.title().text().string()) == "Parakeet v3 Multilingual · on device"
        })
        XCTAssertEqual(try summary.title().text().string(), "Parakeet v3 Multilingual · on device")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition())
    }
}
