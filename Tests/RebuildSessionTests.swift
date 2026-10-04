import XCTest

@testable import AudioWhisper

@MainActor
final class RebuildSessionTests: IsolatedXCTestCase {
    private var starts = 0
    private var stops = 0
    private var cancellations = 0
    private var copies: [String] = []
    private var saved: [String] = []
    private var session: RebuildSession!
    private var captureID: UUID?
    private var interruptionSource = NSObject()
    private var transcribe: ((URL, TranscriptionPipelineConfig, UUID) async throws -> TranscriptionResult)!
    private let ready = RebuildReadiness(
        microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)

    override func setUp() {
        super.setUp()
        starts = 0
        stops = 0
        cancellations = 0
        copies = []
        saved = []
        captureID = nil
        interruptionSource = NSObject()
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        transcribe = { _, _, _ in TranscriptionResult(text: "A useful transcript", correctionOutcome: nil) }
        session = RebuildSession(
            services: RebuildSessionServices(
                start: { id in
                    self.starts += 1
                    self.captureID = id
                    return true
                },
                stop: {
                    self.stops += 1
                    return FileManager.default.temporaryDirectory.appendingPathComponent(
                        "rebuild-\(UUID().uuidString).wav")
                },
                cancel: { self.cancellations += 1 },
                transcribe: { url, config, id in try await self.transcribe(url, config, id) },
                copy: { self.copies.append($0) },
                save: { text, _, _ in self.saved.append(text) },
                interruptionSource: interruptionSource
            ))
    }

    override func tearDown() {
        session.cancel()
        session = nil
        transcribe = nil
        super.tearDown()
    }

    func testReadyRequiresAllPrerequisites() {
        var state = ready
        XCTAssertTrue(state.ready)
        state.microphoneGranted = false
        XCTAssertFalse(state.ready)
        state = ready
        state.modelInstalled = false
        XCTAssertFalse(state.ready)
        state = ready
        state.runtimeReady = false
        XCTAssertFalse(state.ready)
        state = ready
        state.checking = true
        XCTAssertFalse(state.ready)
    }

    func testRepeatedBlockedShortcutsNeverStartAudioOrProcessing() {
        session.readiness = RebuildReadiness(checking: false)
        var setup = 0
        session.openSetup = { setup += 1 }
        for _ in 0..<5 { session.toggleRecording() }
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(stops, 0)
        XCTAssertTrue(copies.isEmpty)
        XCTAssertEqual(setup, 5, "Each request brings forward the same normal setup window")
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.isRequestingMicrophone)
    }

    func testShortcutStartsAndStopsOneSession() async {
        session.readiness = ready
        session.toggleRecording()
        XCTAssertEqual(session.phase, .recording)
        session.toggleRecording()
        await settle()
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(copies, ["A useful transcript"])
        XCTAssertEqual(saved, copies)
        XCTAssertEqual(session.phase, .completed)
    }

    func testCancelSuppressesALateSuccessfulResult() async {
        var pending: CheckedContinuation<TranscriptionResult, Error>?
        transcribe = { _, _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
        session.readiness = ready
        session.toggleRecording()
        session.finishRecording()
        await settle()
        XCTAssertNotNil(pending)
        session.cancel()
        pending?.resume(returning: TranscriptionResult(text: "Old result", correctionOutcome: nil))
        await settle()
        XCTAssertTrue(copies.isEmpty)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertEqual(session.phase, .idle)
    }

    func testBusyShortcutDoesNotStartAnotherRecording() async {
        var pending: CheckedContinuation<TranscriptionResult, Error>?
        transcribe = { _, _, _ in try await withCheckedThrowingContinuation { pending = $0 } }
        session.readiness = ready
        session.toggleRecording()
        session.finishRecording()
        await settle()
        session.toggleRecording()
        session.toggleRecording()
        XCTAssertEqual(starts, 1)
        pending?.resume(returning: TranscriptionResult(text: "Done", correctionOutcome: nil))
        await settle()
    }

    func testSettingsAreCapturedAtStart() async {
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        var captured: WhisperModel?
        transcribe = { _, config, _ in
            captured = config.whisperModel
            return TranscriptionResult(text: "Captured", correctionOutcome: nil)
        }
        session.readiness = ready
        session.toggleRecording()
        AppDefaults.selectedWhisperModel = .tiny
        session.finishRecording()
        await settle()
        XCTAssertEqual(captured, .base)
    }

    func testFilesDoNotRequireMicrophoneAccess() async {
        var fileReady = ready
        fileReady.microphoneGranted = false
        session.readiness = fileReady
        session.importAudio(URL(fileURLWithPath: "/tmp/selected-file.wav"))
        await settle()
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(copies, ["A useful transcript"])
    }

    func testTranscriptionErrorIsInlineAndDoesNotDeliver() async {
        transcribe = { _, _, _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Voice model failed"])
        }
        session.readiness = ready
        session.toggleRecording()
        session.finishRecording()
        await settle()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.notice, "Voice model failed")
        XCTAssertTrue(copies.isEmpty)
    }

    func testCorrectionFailureStillDeliversOriginalAndShowsNotice() async {
        transcribe = { _, _, _ in
            TranscriptionResult(
                text: "Original", correctionOutcome: .failed(NSError(domain: "test", code: 2), fallback: "Original")
            )
        }
        session.readiness = ready
        session.toggleRecording()
        session.finishRecording()
        await settle()
        XCTAssertEqual(copies, ["Original"])
        XCTAssertTrue(session.notice?.contains("original") == true)
    }

    func testApplicationOwnedStorageNeverUsesPersonalFolders() {
        for url in [
            RebuildStorage.root, RebuildStorage.history, RebuildStorage.categories, RebuildStorage.whisperModels
        ] {
            XCTAssertTrue(url.path.contains("/Library/Application Support/AudioWhisper Rebuild"))
            XCTAssertFalse(url.path.contains("/Documents/"))
            XCTAssertFalse(url.path.contains("/Desktop/"))
            XCTAssertFalse(url.path.contains("/Downloads/"))
        }
    }

    func testRetryDoesNotRecordAgainAndDeliversOnce() async {
        var attempts = 0
        transcribe = { _, _, _ in
            attempts += 1
            if attempts == 1 { throw NSError(domain: "test", code: 1) }
            return TranscriptionResult(text: "Recovered transcript", correctionOutcome: nil)
        }
        session.readiness = ready
        session.toggleRecording()
        session.finishRecording()
        await settle()
        XCTAssertTrue(session.canRetry)
        session.retry()
        session.retry()
        await settle()
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(copies, ["Recovered transcript"])
        XCTAssertFalse(session.canRetry)
    }

    func testCancelDiscardsRetry() async {
        transcribe = { _, _, _ in throw NSError(domain: "test", code: 1) }
        session.readiness = ready
        session.importAudio(URL(fileURLWithPath: "/tmp/selected-file.wav"))
        await settle()
        XCTAssertTrue(session.canRetry)
        session.cancel()
        XCTAssertFalse(session.canRetry)
        session.retry()
        XCTAssertEqual(session.phase, .idle)
    }

    func testEmptyResultDoesNotOverwriteClipboardOrHistory() async {
        transcribe = { _, _, _ in TranscriptionResult(text: "  \n  ", correctionOutcome: nil) }
        session.readiness = ready
        session.importAudio(URL(fileURLWithPath: "/tmp/selected-file.wav"))
        await settle()
        XCTAssertEqual(session.phase, .failed)
        XCTAssertTrue(session.canRetry)
        XCTAssertTrue(copies.isEmpty)
        XCTAssertTrue(saved.isEmpty)
    }

    func testModelChangeImmediatelyBlocksRecording() {
        session.readiness = ready
        session.selectionChanged()
        XCTAssertFalse(session.readiness.ready)
        session.toggleRecording()
        XCTAssertEqual(starts, 0)
    }

    func testModelMaintenanceBlocksRecordingAndFileJobs() {
        session.readiness = ready
        session.maintenanceInProgress = true
        session.toggleRecording()
        session.importAudio(URL(fileURLWithPath: "/tmp/selected-file.wav"))
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(session.phase, .idle)
    }

}

extension RebuildSessionTests {
    func testRetryWaitsForMaintenanceAndKeepsItsAudio() async {
        var attempts = 0
        transcribe = { _, _, _ in
            attempts += 1
            if attempts == 1 { throw NSError(domain: "test", code: 1) }
            return TranscriptionResult(text: "Recovered", correctionOutcome: nil)
        }
        session.readiness = ready
        session.importAudio(URL(fileURLWithPath: "/tmp/selected-file.wav"))
        await settle()
        session.maintenanceInProgress = true
        session.retry()
        await settle()
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(session.phase, .failed)
        session.maintenanceInProgress = false
        session.retry()
        await settle()
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(copies, ["Recovered"])
    }

    func testRetryCannotUseReadinessForAnotherModel() async {
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        var attempts = 0
        transcribe = { _, _, _ in
            attempts += 1
            throw NSError(domain: "test", code: 1)
        }
        session.readiness = ready
        session.importAudio(URL(fileURLWithPath: "/tmp/selected-file.wav"))
        await settle()
        AppDefaults.selectedWhisperModel = .tiny
        session.readiness = ready
        session.retry()
        await settle()
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(session.phase, .failed)
    }

    func testFailedCaptureInterruptionLeavesListeningAndClosesRecorder() throws {
        var closed = 0
        session.closeRecorder = { closed += 1 }
        session.readiness = ready
        session.toggleRecording()
        let id = try XCTUnwrap(captureID)
        NotificationCenter.default.post(
            name: .recordingInterrupted,
            object: interruptionSource,
            userInfo: ["event": RecordingInterruption.failed(sessionID: id, message: "Microphone disconnected")]
        )
        XCTAssertEqual(session.phase, .failed)
        XCTAssertEqual(session.notice, "Microphone disconnected")
        XCTAssertEqual(closed, 1)
        XCTAssertTrue(copies.isEmpty)
    }

    func testGracefulInterruptionTranscribesCapturedAudioExactlyOnce() async throws {
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("interrupted-\(UUID()).wav")
        try Data("captured audio".utf8).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        session.readiness = ready
        session.toggleRecording()
        let id = try XCTUnwrap(captureID)
        let event = RecordingInterruption.finished(sessionID: id, audio: audio, duration: 2.5)
        NotificationCenter.default.post(name: .recordingInterrupted, object: interruptionSource, userInfo: ["event": event])
        NotificationCenter.default.post(name: .recordingInterrupted, object: interruptionSource, userInfo: ["event": event])
        await settle()
        XCTAssertEqual(session.phase, .completed)
        XCTAssertEqual(copies, ["A useful transcript"])
        XCTAssertEqual(session.duration, 2.5)
        XCTAssertEqual(stops, 0, "The recorder already stopped before publishing its audio")
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testOldInterruptionCannotStopANewerCaptureAndCleansOwnedAudio() throws {
        session.readiness = ready
        session.toggleRecording()
        let oldID = try XCTUnwrap(captureID)
        session.cancel()
        session.toggleRecording()
        let audio = FileManager.default.temporaryDirectory.appendingPathComponent("stale-\(UUID()).wav")
        try Data("old audio".utf8).write(to: audio)
        defer { try? FileManager.default.removeItem(at: audio) }
        NotificationCenter.default.post(
            name: .recordingInterrupted,
            object: interruptionSource,
            userInfo: ["event": RecordingInterruption.finished(sessionID: oldID, audio: audio, duration: 1)]
        )
        XCTAssertEqual(session.phase, .recording)
        XCTAssertTrue(copies.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
