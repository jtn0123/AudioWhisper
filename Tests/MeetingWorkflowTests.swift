import XCTest
import AVFAudio
@testable import AudioWhisper

@MainActor
final class MeetingWorkflowTests: IsolatedXCTestCase {
    func testCancellationAfterCommitPreservesCompletedNotesAndDeletedAudioState() async throws {
        let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let draining = expectation(description: "Successful worker cleanup started")
        var release: CheckedContinuation<Void, Never>?
        let services = MeetingProcessingServices(modelInstalled: { _ in true }, transcribe: { _, _, _, _, _ in
            [.init(source: .system, start: 0, end: 1, text: "Meeting fixture")]
        }, clearVoiceCache: {}, speakers: { document, _ in document.segments }, summaryReady: { _ in true },
        summarize: { _, _ in "Completed meeting notes" }, shutdown: {
            draining.fulfill()
            await withCheckedContinuation { release = $0 }
        })
        let session = RebuildMeetingSession(dictation: nil, store: store, capture: FakeMeetingCapture()) {
            try await MeetingProcessor(store: store, services: services).process($0, options: $1, progress: $2)
        }
        session.makeSummary = true
        session.start()
        try await wait { session.activity == .capturing }
        await session.stop()
        session.processCurrent()
        await fulfillment(of: [draining], timeout: 5)
        let id = try XCTUnwrap(session.document?.id)
        XCTAssertEqual(try store.load(id).status, .complete)
        XCTAssertFalse(try store.load(id).audioRetained)
        session.cancelProcessing()
        release?.resume()
        try await wait { !session.busy }
        let committed = try store.load(id)
        XCTAssertEqual(session.document?.status, .complete)
        XCTAssertEqual(committed.status, .complete)
        XCTAssertEqual(committed.summary, "Completed meeting notes")
        XCTAssertFalse(committed.audioRetained)
    }

    func testDelayedFailureFromPreviousMeetingCannotStopReplacement() async throws {
        let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let capture = FakeMeetingCapture()
        let session = RebuildMeetingSession(dictation: nil, store: store, capture: capture)
        session.start()
        try await wait { session.activity == .capturing }
        await session.stop()
        session.start()
        try await wait { session.activity == .capturing }
        let replacement = session.document?.id
        capture.failures[0]("Delayed old stream failure")
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(session.activity, .capturing)
        XCTAssertEqual(session.document?.id, replacement)
        await session.stop()
    }

    func testFinishWaitsForAnAdmittedBufferBeforeClosingAndReturningChunks() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let admitted = expectation(description: "Buffer admitted before copy")
        let release = DispatchSemaphore(value: 0)
        let sink = MeetingAudioSink(folder: folder, source: .system, epoch: 100,
            closed: { _ in }, failed: { _ in XCTFail("Unexpected audio failure") }, copyBuffer: { buffer in
                admitted.fulfill()
                _ = release.wait(timeout: .now() + 5)
                return MeetingAudioSink.copy(buffer)
            })
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        DispatchQueue.global().async { sink.append(buffer, time: 100) }
        await fulfillment(of: [admitted], timeout: 5)
        var finished = false
        let stop = Task { let chunks = await sink.finish(); finished = true; return chunks }
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(finished, "Stop must drain buffers admitted before it closed admission")
        release.signal()
        let chunks = await stop.value
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.duration ?? 0, 0.1, accuracy: 0.001)
    }

    func testCancellationKeepsDictationReservedUntilMeetingWorkerCleanupFinishes() async throws {
        let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let dictation = RebuildSession(services: .init(start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in .init(text: "Unused", correctionOutcome: nil) }, copy: { _ in }, save: { _, _, _ in }))
        let started = expectation(description: "Notes generation started")
        let draining = expectation(description: "Scoped worker cleanup started")
        var release: CheckedContinuation<Void, Never>?
        let services = MeetingProcessingServices(modelInstalled: { _ in true }, transcribe: { _, _, _, _, _ in
            [.init(source: .system, start: 0, end: 1, text: "Meeting fixture")]
        }, clearVoiceCache: {}, speakers: { document, _ in document.segments }, summaryReady: { _ in true },
        summarize: { _, _ in
            started.fulfill()
            try await Task.sleep(for: .seconds(60))
            return "Unused"
        }, shutdown: {
            draining.fulfill()
            await withCheckedContinuation { release = $0 }
        })
        let session = RebuildMeetingSession(dictation: dictation, store: store, capture: FakeMeetingCapture()) {
            try await MeetingProcessor(store: store, services: services).process($0, options: $1, progress: $2)
        }
        session.makeSummary = true
        session.start()
        try await wait { session.activity == .capturing }
        await session.stop()
        session.processCurrent()
        await fulfillment(of: [started], timeout: 5)
        session.cancelProcessing()
        await fulfillment(of: [draining], timeout: 5)
        XCTAssertTrue(session.busy)
        XCTAssertTrue(dictation.maintenanceInProgress)
        release?.resume()
        try await wait { !session.busy }
        XCTAssertFalse(dictation.maintenanceInProgress)
        XCTAssertEqual(session.document?.status, .interrupted)
        XCTAssertTrue(session.document?.audioRetained == true)
    }

    func testStaleStartupCannotStopAReplacementCapture() async throws {
        var firstStart: CheckedContinuation<Void, Never>?
        var calls = 0
        let capture = MeetingNativeCapture(startupForTesting: {
            calls += 1
            if calls == 1 { await withCheckedContinuation { firstStart = $0 } }
        })
        let first = Task {
            try await capture.start(folder: FileManager.default.temporaryDirectory, microphone: false, system: true,
                                    closed: { _ in }, failed: { _ in })
        }
        try await wait { firstStart != nil }
        _ = await capture.stop()
        try await capture.start(folder: FileManager.default.temporaryDirectory, microphone: false, system: true,
                                closed: { _ in }, failed: { _ in })
        let replacement = try XCTUnwrap(capture.identity)
        firstStart?.resume()
        do { try await first.value; XCTFail("Stale startup must fail") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertEqual(capture.identity, replacement)
        _ = await capture.stop()
    }

    func testUnfinishedFolderDoesNotHideOtherMeetings() throws {
        let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        var valid = MeetingDocument(title: "Readable")
        valid.status = .captured
        try store.save(valid)
        try FileManager.default.createDirectory(at: store.folder(UUID()), withIntermediateDirectories: true)
        let inventory = try store.list()
        XCTAssertEqual(inventory.entries.map(\.id), [valid.id])
        XCTAssertEqual(inventory.unreadableCount, 1)
        XCTAssertFalse(inventory.hasMore)
    }

    func testClosedCAFChunksRecoverAfterAnUnfinishedManifest() async throws {
        let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let document = MeetingDocument(title: "Recover me")
        try store.save(document)
        let sink = MeetingAudioSink(folder: store.folder(document.id), source: .microphone,
                                    epoch: 100, closed: { _ in }, failed: { _ in XCTFail("Unexpected audio write failure") })
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600))
        buffer.frameLength = 1_600
        for index in 0..<1_600 { buffer.floatChannelData?[0][index] = sin(Float(index) * 0.1) * 0.2 }
        sink.append(buffer, time: 100)
        sink.append(buffer, time: 100.1)
        sink.append(buffer, time: 130)
        let chunks = await sink.finish()
        XCTAssertEqual(chunks.count, 2, "A timestamp gap must start a new chunk instead of shifting the meeting timeline")
        XCTAssertEqual(chunks[0].duration, 0.2, accuracy: 0.001)
        XCTAssertEqual(chunks[1].offset, 30, accuracy: 0.001)
        let recovered = try store.load(document.id)
        XCTAssertEqual(recovered.status, .interrupted)
        XCTAssertEqual(Set(recovered.chunks.map(\.id)), Set(chunks.map(\.id)))
        XCTAssertTrue(recovered.audioRetained)
        XCTAssertThrowsError(try store.audioURL(document.id, filename: "../outside.caf"))
        let audio = try AVAudioFile(forReading: store.audioURL(document.id, filename: chunks[0].filename))
        XCTAssertEqual(audio.length, 3_200)
    }

    func testProcessingFailureKeepsSourcesAndReleasesTheDictationReservation() async throws {
        let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let dictation = RebuildSession(services: .init(start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }, capturePasteDestination: { nil }))
        let capture = FakeMeetingCapture()
        let session = RebuildMeetingSession(dictation: dictation, store: store, capture: capture) { _, _, _ in
            throw MeetingError.model
        }
        session.start()
        try await wait { session.activity == .capturing }
        XCTAssertTrue(dictation.maintenanceInProgress)
        await session.stop()
        XCTAssertFalse(dictation.maintenanceInProgress)
        XCTAssertEqual(session.document?.status, .captured)
        let document = try XCTUnwrap(session.document)
        let audio = try store.audioURL(document.id, filename: capture.chunk.filename)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        session.processCurrent()
        try await wait { !session.busy }
        XCTAssertEqual(session.document?.status, .failed)
        XCTAssertTrue(session.document?.audioRetained == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(dictation.maintenanceInProgress)
        XCTAssertNotNil(session.error)
    }

    func testNativeCaptureRefusesHardwareUnderXCTest() async throws {
        do {
            try await MeetingNativeCapture().start(folder: FileManager.default.temporaryDirectory,
                microphone: true, system: true, closed: { _ in }, failed: { _ in })
            XCTFail("Tests must not request capture permissions or open real devices")
        } catch { XCTAssertEqual(error as? MeetingError, .audio) }
    }

    func testSpeakerOverlapAndSummaryBoundsDoNotInventIdentities() {
        let spans = [MeetingSpeakerSpan(start: 0, end: 2, label: "Speaker 0"),
                     MeetingSpeakerSpan(start: 2, end: 4, label: "Speaker 1")]
        XCTAssertEqual(MeetingProcessor.speakerLabel(start: 0.1, end: 1.8, spans: spans), "Speaker 0")
        XCTAssertEqual(MeetingProcessor.speakerLabel(start: 1, end: 3, spans: spans), "Multiple speakers")
        XCTAssertEqual(MeetingProcessor.speakerLabel(start: 8, end: 9, spans: spans), "Unknown speaker")
        let text = String(repeating: "abc 👩🏽‍💻\n", count: 2_000)
        let chunks = MeetingProcessor.summaryChunks(text)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.unicodeScalars.count <= 8_000 })
    }

    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class FakeMeetingCapture: MeetingCapturing {
    var failures: [@Sendable (String) -> Void] = []
    let chunk = MeetingAudioChunk(id: UUID(), source: .system, filename: "fixture.caf", offset: 0, duration: 1)
    func start(folder: URL, microphone: Bool, system: Bool,
               closed: @escaping @Sendable (MeetingAudioChunk) -> Void,
               failed: @escaping @Sendable (String) -> Void) async throws {
        failures.append(failed)
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent(chunk.filename))
        closed(chunk)
    }
    func stop() async -> [MeetingAudioChunk] { [chunk] }
}
