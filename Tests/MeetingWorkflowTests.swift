import AVFoundation
import XCTest
@testable import AudioWhisper

@MainActor
final class MeetingWorkflowTests: IsolatedXCTestCase {
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
    let chunk = MeetingAudioChunk(id: UUID(), source: .system, filename: "fixture.caf", offset: 0, duration: 1)
    func start(folder: URL, microphone: Bool, system: Bool,
               closed: @escaping @Sendable (MeetingAudioChunk) -> Void,
               failed: @escaping @Sendable (String) -> Void) async throws {
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent(chunk.filename))
        closed(chunk)
    }
    func stop() async -> [MeetingAudioChunk] { [chunk] }
}
