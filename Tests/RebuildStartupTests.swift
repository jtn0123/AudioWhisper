import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildStartupTests: IsolatedXCTestCase {
    private let ready = RebuildReadiness(
        microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)

    private func makeSession(start: @escaping (UUID) async -> Bool, cancel: @escaping () -> Void = {}) -> RebuildSession {
        RebuildSession(services: RebuildSessionServices(
            start: { _ in XCTFail("Live startup must use the async path"); return false },
            stop: { nil }, cancel: cancel,
            transcribe: { _, _, _ in TranscriptionResult(text: "Unused", correctionOutcome: nil) },
            copy: { _ in XCTFail("Preparation must not deliver a transcript") },
            save: { _, _, _ in XCTFail("Preparation must not update history or usage") },
            startError: { "The microphone took too long to connect." }, startAsync: start))
    }

    func testPendingHardwareStartBlocksRepeatedActionsAndRemainsCancellable() async {
        var continuation: CheckedContinuation<Bool, Never>?
        var starts = 0
        var cancels = 0
        let session = makeSession(start: { _ in
            starts += 1
            return await withCheckedContinuation { continuation = $0 }
        }, cancel: { cancels += 1 })
        session.readiness = ready
        session.toggleRecording()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.phase, .starting)
        XCTAssertTrue(session.phase.isBusy)
        XCTAssertFalse(session.canToggleRecording)
        XCTAssertFalse(session.canImportAudio)
        for _ in 0..<5 { session.toggleRecording() }
        XCTAssertEqual(starts, 1)
        session.cancel()
        continuation?.resume(returning: true)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.phase, .idle, "Late startup must not revive cancelled recording")
        XCTAssertEqual(cancels, 1)
    }

    func testFailedAsyncStartSurfacesReasonAndAllowsRetry() async {
        let session = makeSession(start: { _ in false })
        session.readiness = ready
        session.toggleRecording()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.notice, "The microphone took too long to connect.")
        XCTAssertTrue(session.canToggleRecording)
        XCTAssertFalse(session.hasRetryAudio)
    }

    func testSuccessfulAsyncStartShowsRecorderOnce() async {
        var shown = 0
        let session = makeSession(start: { _ in true })
        AppDefaults.immediateRecording = false
        session.showRecorder = { shown += 1 }
        session.readiness = ready
        session.toggleRecording()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.phase, .recording)
        XCTAssertEqual(shown, 1)
        session.cancel()
    }
}
