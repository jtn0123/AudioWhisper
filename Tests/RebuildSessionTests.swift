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
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        transcribe = { _, _, _ in TranscriptionResult(text: "A useful transcript", correctionOutcome: nil) }
        session = RebuildSession(
            services: RebuildSessionServices(
                start: {
                    self.starts += 1
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
                save: { text, _, _ in self.saved.append(text) }
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

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}
