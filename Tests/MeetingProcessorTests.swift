import XCTest
@testable import AudioWhisper

@MainActor
final class MeetingProcessorTests: IsolatedXCTestCase {
    func testChunksAreOrderedCheckpointedAndRemovedOnlyAfterSuccess() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var calls: [Double] = []
        var cleared = false
        var services = fixture.services
        services.transcribe = { _, model, language, source, offset in
            XCTAssertEqual(model, .base)
            XCTAssertEqual(language, .french)
            XCTAssertEqual(source, .system)
            if offset > 0 { XCTAssertEqual(try fixture.store.load(fixture.document.id).segments.count, 1) }
            calls.append(offset)
            return [.init(source: source, start: offset, end: offset + 1, text: "Chunk \(offset)")]
        }
        services.clearVoiceCache = { cleared = true }
        var checkpoints: [Int] = []
        let processor = MeetingProcessor(store: fixture.store, services: services)
        let result = try await processor.process(fixture.document,
            options: .init(model: .base, language: .french, summaryModel: "local/fixture")) { document, _ in
                checkpoints.append(document.segments.count)
            }
        XCTAssertEqual(calls, [0, 20])
        XCTAssertEqual(checkpoints, [1, 2])
        XCTAssertTrue(cleared)
        XCTAssertEqual(result.status, .complete)
        XCTAssertFalse(result.audioRetained)
        XCTAssertEqual(try fixture.store.load(result.id).segments, result.segments)
        for chunk in result.chunks {
            let url = try fixture.store.audioURL(result.id, filename: chunk.filename)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testSpeakerEstimatesAndSummaryUseTranscriptAndKeepAudioPreference() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var services = fixture.services
        var speakerCalls = 0
        services.speakers = { document, folder in
            speakerCalls += 1
            XCTAssertEqual(folder, "/installed/speaker")
            return document.segments.map { segment in var copy = segment; copy.speaker = "Cluster 0"; return copy }
        }
        services.summarize = { text, model in
            XCTAssertTrue(text.contains("Cluster 0"))
            XCTAssertEqual(model, "local/summary")
            return "Decision: review the draft."
        }
        let result = try await MeetingProcessor(store: fixture.store, services: services).process(fixture.document,
            options: .init(model: .base, speakerModelFolder: "/installed/speaker", summarize: true,
                           summaryModel: "local/summary", keepAudio: true)) { _, _ in }
        XCTAssertEqual(speakerCalls, 1)
        XCTAssertEqual(result.summary, "Decision: review the draft.")
        XCTAssertTrue(result.audioRetained)
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.segments.map(\.speaker), ["Cluster 0", "Cluster 0"])
    }

    func testUnavailableSummaryAndFailedRecognitionKeepCheckpointAndAudio() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var services = fixture.services
        services.summaryReady = { _ in false }
        let processor = MeetingProcessor(store: fixture.store, services: services)
        do {
            _ = try await processor.process(fixture.document,
                options: .init(model: .base, summarize: true, summaryModel: "missing")) { _, _ in }
            XCTFail("Missing summary assets must surface a recoverable failure")
        } catch { XCTAssertEqual(error as? PublicAutomationError, .assets) }
        let checkpoint = try fixture.store.load(fixture.document.id)
        XCTAssertEqual(checkpoint.segments.count, 2)
        XCTAssertEqual(checkpoint.status, .interrupted)
        XCTAssertTrue(checkpoint.audioRetained)
        services.transcribe = { _, _, _, _, offset in
            if offset > 0 { throw MeetingError.audio }
            return [.init(source: .system, start: 0, end: 1, text: "First chunk survived")]
        }
        do {
            _ = try await MeetingProcessor(store: fixture.store, services: services).process(fixture.document,
                options: .init(model: .base, summaryModel: "local")) { _, _ in }
            XCTFail("Recognition errors must propagate")
        } catch { XCTAssertEqual(error as? MeetingError, .audio) }
        XCTAssertEqual(try fixture.store.load(fixture.document.id).segments.map(\.text), ["First chunk survived"])
    }

    func testSilentChunksAndMissingModelNeverReportSuccessfulMeeting() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var document = fixture.document
        document.chunks = document.chunks.map { chunk in var copy = chunk; copy.hasSignal = false; return copy }
        var services = fixture.services
        services.transcribe = { _, _, _, _, _ in XCTFail("Silent chunks need no inference"); return [] }
        do {
            _ = try await MeetingProcessor(store: fixture.store, services: services).process(document,
                options: .init(model: .base, summaryModel: "local")) { _, _ in }
            XCTFail("Silence must not become a complete transcript")
        } catch SpeechToTextError.noSpeechDetected {
            // Expected: silence remains a recoverable recognition failure.
        } catch { XCTFail("Unexpected error: \(error)") }
        services.modelInstalled = { _ in false }
        do {
            _ = try await MeetingProcessor(store: fixture.store, services: services).process(document,
                options: .init(model: .base, summaryModel: "local")) { _, _ in }
            XCTFail("Model installation is an explicit setup step")
        } catch { XCTAssertEqual(error as? MeetingError, .model) }
    }

    private struct Fixture {
        let store: MeetingStore
        let document: MeetingDocument
        init() throws {
            store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
            var document = MeetingDocument(title: "Meeting processing fixture")
            document.status = .captured
            document.chunks = [20.0, 0].map { offset in
                .init(id: UUID(), source: .system, filename: "chunk-\(Int(offset)).caf", offset: offset, duration: 1)
            }
            try store.save(document)
            for chunk in document.chunks { try Data([1]).write(to: store.audioURL(document.id, filename: chunk.filename)) }
            self.document = document
        }
        var services: MeetingProcessingServices {
            .init(modelInstalled: { _ in true }, transcribe: { _, _, _, source, offset in
                [.init(source: source, start: offset, end: offset + 1, text: "Review the draft.")]
            }, clearVoiceCache: {}, speakers: { document, _ in document.segments },
                  summaryReady: { _ in true }, summarize: { _, _ in "Notes" })
        }
        func remove() { try? FileManager.default.removeItem(at: store.root) }
    }
}
