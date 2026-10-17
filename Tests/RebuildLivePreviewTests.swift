import XCTest
import ViewInspector
@testable import AudioWhisper

private actor PreviewWorkerProbe {
    private(set) var calls = 0
    private var waiting: [CheckedContinuation<String, Error>] = []
    func recognize() async throws -> String {
        calls += 1
        return try await withCheckedThrowingContinuation { waiting.append($0) }
    }
    func finish(_ text: String) { waiting.removeFirst().resume(returning: text) }
    func fail() { waiting.removeFirst().resume(throwing: ParakeetError.emptyAudio) }
}

@MainActor
final class RebuildLivePreviewTests: IsolatedXCTestCase {
    private let sample = RecordingPreviewSnapshot(samples: [Float](repeating: 0.1, count: 16000), sampleRate: 16000)

    func testUnchangedCaptureFramesAreNotRecognizedAgain() async throws {
        let worker = PreviewWorkerProbe()
        let preview = RebuildLivePreview(interval: .milliseconds(1)) { _, _ in try await worker.recognize() }
        var frame: Int64 = 16000
        preview.start(model: .v2English) {
            RecordingPreviewSnapshot(samples: self.sample.samples, sampleRate: 16000, endFrame: frame)
        }
        try await waitFor { await worker.calls == 1 }
        await worker.finish("A first draft")
        try await waitFor { preview.text == "A first draft" }
        try await Task.sleep(for: .milliseconds(15))
        let calls = await worker.calls
        XCTAssertEqual(calls, 1)
        frame = 32000
        try await waitFor { await worker.calls == 2 }
        await worker.finish("A first draft with more words")
        try await waitFor { preview.text == "A first draft with more words" }
        XCTAssertEqual(preview.stablePrefix, "A first draft ")
        preview.stop(clear: true)
    }

    func testDraftPrefixNeverClaimsTheChangingTailIsFinal() {
        XCTAssertEqual(RebuildLivePreview.sharedPrefix("one two three", "one two three four"), "one two ")
        XCTAssertEqual(RebuildLivePreview.sharedPrefix("wrong words", "different words"), "")
        XCTAssertEqual(RebuildLivePreview.sharedPrefix("", "first words"), "")
    }

    override func tearDown() {
        for key in [AppDefaults.Key.liveTranscriptionPreview, .transcriptionProvider, .enableSmartPaste] {
            AppDefaults.defaults.removeObject(forKey: key.rawValue)
        }
        super.tearDown()
    }

    func testCancelledDraftNeverUpdatesTheDisplay() async throws {
        let worker = PreviewWorkerProbe()
        let preview = RebuildLivePreview(interval: .milliseconds(1)) { _, _ in try await worker.recognize() }
        preview.start(model: .v2English) { self.sample }
        try await waitFor { await worker.calls == 1 }
        preview.stop(clear: true)
        await worker.finish("Late cancelled words")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(preview.text, "")
        XCTAssertFalse(preview.enabled)
        XCTAssertFalse(preview.updating)
    }

    func testPreviewShowsTheDraftAndPreservesItWithAnHonestPauseMessage() async throws {
        let worker = PreviewWorkerProbe()
        let preview = RebuildLivePreview(interval: .milliseconds(1)) { _, _ in try await worker.recognize() }
        let view = RebuildLivePreviewView(preview: preview)
        preview.start(model: .v2English) { self.sample }
        try await waitFor { await worker.calls == 1 }
        _ = try view.inspect().find(text: "Listening for speech…")
        _ = try view.inspect().find(text: "Updating…")
        await worker.finish("These words are a draft.")
        try await waitFor { preview.text == "These words are a draft." }
        _ = try view.inspect().find(text: "These words are a draft.")
        try await waitFor { await worker.calls == 2 }
        await worker.fail()
        try await waitFor { preview.paused }
        _ = try view.inspect().find(text: "Preview paused. Your recording will still be transcribed.")
        _ = try view.inspect().find(text: "These words are a draft.")
        XCTAssertThrowsError(try view.inspect().find(button: "Copy"), "Drafts have no delivery action")
        preview.stop(clear: true)
    }

    func testReplacementWaitsForExistingInferenceAndRejectsItsResult() async throws {
        let worker = PreviewWorkerProbe()
        let preview = RebuildLivePreview(interval: .milliseconds(1)) { _, _ in try await worker.recognize() }
        preview.start(model: .v2English) { self.sample }
        try await waitFor { await worker.calls == 1 }
        preview.start(model: .v3Multilingual) { self.sample }
        try await Task.sleep(for: .milliseconds(15))
        let pending = await worker.calls
        XCTAssertEqual(pending, 1, "Rapid replacement must not queue preview jobs behind final transcription")
        await worker.finish("Old session")
        try await waitFor { await worker.calls == 2 }
        XCTAssertEqual(preview.text, "")
        await worker.finish("New session words")
        try await waitFor { preview.text == "New session words" }
        preview.stop(clear: true)
    }

    func testPreviewFailureDoesNotStopCaptureOrDeliverADraft() async throws {
        AppDefaults.liveTranscriptionPreview = true
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.enableSmartPaste = false
        let preview = RebuildLivePreview(interval: .milliseconds(1)) { _, _ in throw ParakeetError.emptyAudio }
        var copies: [String] = []
        var saves = 0
        var enabled: [Bool] = []
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0]).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { audio }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "Final words", correctionOutcome: nil) },
            copy: { copies.append($0) }, save: { _, _, _ in saves += 1 })
        services.configureLivePreview = { enabled.append($0) }
        services.previewSnapshot = { self.sample }
        let session = RebuildSession(services: services, livePreview: preview)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.toggleRecording()
        try await waitFor { preview.message.hasPrefix("Preview paused") }
        XCTAssertEqual(enabled, [true])
        XCTAssertEqual(session.phase, .recording)
        XCTAssertTrue(copies.isEmpty)
        XCTAssertEqual(saves, 0)
        session.finishRecording()
        try await waitFor { session.phase == .completed }
        XCTAssertEqual(copies, ["Final words"])
        XCTAssertEqual(saves, 1)
        session.cancel()
    }

    func testWhisperKeepsThePreferenceButNeverStartsParakeetPreview() {
        AppDefaults.liveTranscriptionPreview = true
        AppDefaults.transcriptionProvider = .local
        var enabled: [Bool] = []
        var services = RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in XCTFail("No preview may deliver text") }, save: { _, _, _ in })
        services.configureLivePreview = { enabled.append($0) }
        let session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.toggleRecording()
        XCTAssertEqual(enabled, [false])
        XCTAssertFalse(session.livePreview.enabled)
        XCTAssertTrue(AppDefaults.liveTranscriptionPreview)
        session.cancel()
    }

    private func waitFor(_ condition: () async -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await condition()), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        let passed = await condition()
        XCTAssertTrue(passed)
    }
}
