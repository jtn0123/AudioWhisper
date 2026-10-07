import AppKit
import SwiftData
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildDeliveryIntegrationTests: IsolatedXCTestCase {
    private var history: DataManager!
    private var usage: UsageMetricsStore!
    private var clipboard: NSPasteboard!
    private var speech: StubSpeechToTextServiceForFlow!
    private var session: RebuildSession!
    private var audio: URL!

    override func setUp() async throws {
        try await super.setUp()
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        AppDefaults.semanticCorrectionMode = .off
        AppDefaults.transcriptionHistoryEnabled = true
        AppDefaults.transcriptionRetentionPeriod = .forever
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        let container = try ModelContainer(
            for: TranscriptionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        history = DataManager(modelContainer: container)
        usage = UsageMetricsStore(defaults: AppDefaults.defaults)
        usage.reset()
        clipboard = NSPasteboard(name: NSPasteboard.Name("rebuild-delivery-\(UUID())"))
        speech = StubSpeechToTextServiceForFlow()
        speech.result = .success("hello world")
        audio = FileManager.default.temporaryDirectory.appendingPathComponent("rebuild-delivery-\(UUID()).wav")
        let fixture = try XCTUnwrap(Bundle.module.url(
            forResource: "speech_sample", withExtension: "wav", subdirectory: "Resources"))
        try FileManager.default.copyItem(at: fixture, to: audio)
    }

    override func tearDown() async throws {
        session?.cancel()
        try? FileManager.default.removeItem(at: audio)
        clipboard.releaseGlobally()
        session = nil
        speech = nil
        history = nil
        usage = nil
        try await super.tearDown()
    }

    func testLiveAssemblyDeliversRawTextMetadataAndUsage() async throws {
        var captured: TranscriptionPipelineConfig?
        speech.handler = { _ in
            captured = TranscriptionProgress.pipelineConfig
            return "hello world"
        }
        makeSession()
        try await record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(clipboard.string(forType: .string), "hello world")
        let records = try await history.fetchAllRecords()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.text, "hello world")
        XCTAssertEqual(record.provider, TranscriptionProvider.local.rawValue)
        XCTAssertEqual(record.modelUsed, WhisperModel.base.rawValue)
        XCTAssertEqual(record.sourceAppBundleId, captured?.sourceAppBundleId)
        XCTAssertNotNil(record.duration)
        XCTAssertEqual(record.wordCount, 2)
        XCTAssertEqual(usage.snapshot.totalSessions, 1)
        XCTAssertEqual(usage.snapshot.totalWords, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testLiveAssemblyDeliversCorrectedText() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        AppDefaults.semanticCorrectionMode = .localMLX
        makeSession(correctionFails: false)
        try await record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(clipboard.string(forType: .string), "Hello world.")
        let records = try await history.fetchAllRecords()
        XCTAssertEqual(records.first?.text, "Hello world.")
        XCTAssertNil(session.notice)
    }

    func testCorrectionFailurePreservesRawDeliveryAndWarning() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        AppDefaults.semanticCorrectionMode = .localMLX
        makeSession(correctionFails: true)
        try await record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(clipboard.string(forType: .string), "hello world")
        let records = try await history.fetchAllRecords()
        XCTAssertEqual(records.first?.text, "hello world")
        XCTAssertTrue(session.notice?.contains("original transcript") == true)
    }

    func testSuccessfulCleanupRetainsOriginalAndCanBeRestoredWithoutAnotherDelivery() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        AppDefaults.semanticCorrectionMode = .localMLX
        makeSession()
        var deliveries = 0
        session.didDeliver = { deliveries += 1 }
        try await record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(session.transcript, "Hello world.")
        XCTAssertEqual(session.originalTranscript, "hello world")
        let records = try await history.fetchAllRecords()
        XCTAssertEqual(records.first?.originalText, "hello world")
        session.useOriginalTranscript()
        XCTAssertEqual(session.transcript, "hello world")
        XCTAssertEqual(clipboard.string(forType: .string), "hello world")
        XCTAssertEqual(deliveries, 1, "Restoring must not trigger another automatic delivery")
        XCTAssertEqual(usage.snapshot.totalSessions, 1)
        let restoredRecords = try await history.fetchAllRecords()
        XCTAssertEqual(restoredRecords.count, 1)
    }

    func testHistoryOffRetainsOriginalOnlyInCurrentSession() async throws {
        try XCTSkipUnless(Arch.isAppleSilicon)
        AppDefaults.semanticCorrectionMode = .localMLX
        AppDefaults.transcriptionHistoryEnabled = false
        makeSession()
        try await record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(session.originalTranscript, "hello world")
        let records = try await history.fetchAllRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testRealHistoryFailurePreservesClipboardAndDeliveredUsage() async throws {
        history.modelContainer = nil
        makeSession()
        try await record()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(clipboard.string(forType: .string), "hello world")
        XCTAssertEqual(usage.snapshot.totalSessions, 1)
        XCTAssertTrue(session.notice?.contains("history could not be saved") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testCancelledOwnedCaptureCannotDeliverLateResult() async throws {
        try await verifyCancellation(imported: false)
    }

    func testCancelledImportPreservesUserAudio() async throws {
        try await verifyCancellation(imported: true)
    }

    func testFailedCaptureRetainsAudioUntilSuccessfulRetry() async throws {
        speech.result = .failure(SpeechToTextError.transcriptionFailed("Fixture failure"))
        makeSession()
        try await record()
        try await waitFor { self.session.phase == .failed }
        XCTAssertTrue(session.hasRetryAudio)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertNil(clipboard.string(forType: .string))
        speech.result = .success("retried words")
        session.retry()
        try await waitFor { self.session.phase == .completed }
        XCTAssertEqual(clipboard.string(forType: .string), "retried words")
        let records = try await history.fetchAllRecords()
        XCTAssertEqual(records.map(\.text), ["retried words"])
        XCTAssertEqual(usage.snapshot.totalSessions, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }

    func testCancelDiscardsOwnedRetryAudio() async throws {
        speech.result = .failure(SpeechToTextError.transcriptionFailed("Fixture failure"))
        makeSession()
        try await record()
        try await waitFor { self.session.phase == .failed }
        session.cancel()
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertEqual(usage.snapshot.totalSessions, 0)
    }

    private func makeSession(correctionFails: Bool = false) {
        let correction = SemanticCorrectionService(
            mlxService: MLXCorrectionService(daemon: RebuildDeliveryDaemon(fails: correctionFails)),
            preparePython: { URL(fileURLWithPath: "/unused-fixture-interpreter") })
        let pipeline = TranscriptionPipeline(speechService: speech, correctionService: correction)
        let board = clipboard!
        var services = RebuildSessionServices.live(
            recorder: AudioEngineRecorder(), pipeline: pipeline,
            copy: { board.clearContents(); board.setString($0, forType: .string) }, history: history, usage: usage)
        // Replace hardware only. The launched factory's real pipeline/delivery stays intact.
        services.startAsync = { _ in true }
        services.stop = { self.audio }
        services.cancel = {}
        session = RebuildSession(services: services)
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
    }

    private func record() async throws {
        session.toggleRecording()
        try await waitFor { self.session.phase == .recording }
        session.finishRecording()
    }

    private func verifyCancellation(imported: Bool) async throws {
        let entered = expectation(description: "Provider entered real pipeline")
        var continuation: CheckedContinuation<String, Error>?
        speech.handler = { _ in
            try await withCheckedThrowingContinuation {
                continuation = $0
                entered.fulfill()
            }
        }
        makeSession()
        if imported { session.importAudio(audio) } else { try await record() }
        await fulfillment(of: [entered], timeout: 2)
        session.cancel()
        try XCTUnwrap(continuation).resume(returning: "late speech")
        try await waitFor { !imported ? !FileManager.default.fileExists(atPath: self.audio.path) : self.speech.callCount == 1 }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(clipboard.string(forType: .string))
        let records = try await history.fetchAllRecords()
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(usage.snapshot.totalSessions, 0)
        XCTAssertEqual(FileManager.default.fileExists(atPath: audio.path), imported)
        XCTAssertEqual(session.phase, .idle)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition(), "Delivery/cleanup did not reach the expected state")
    }
}

private final class RebuildDeliveryDaemon: MLDaemonManaging {
    let fails: Bool
    init(fails: Bool) { self.fails = fails }
    func correct(repo: String, text: String, prompt: String?) async throws -> String {
        if fails { throw MLDaemonError.remoteError("Fixture correction failure") }
        return "Hello world."
    }
    func ping() async -> Bool { true }
}
