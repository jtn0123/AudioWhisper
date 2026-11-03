import XCTest
@testable import AudioWhisper

final class DiagnosticHistoryTests: XCTestCase {
    private func record(id: UUID = UUID(), age: TimeInterval = 0) -> DiagnosticRecord {
        let date = Date().addingTimeInterval(-age)
        return .init(id: id, started: date, finished: date, build: "test-build", system: "test-system",
                     architecture: "arm64", entry: .recording, provider: "local", voiceModel: "base",
                     preferredInput: false, outcome: .completed, delivery: .copied, spans: [], resources: [])
    }

    func testRestartRetentionAndPrivateFilePermissions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recent.json")
        let store = DiagnosticStore(file: file)
        await store.append(record(age: 8 * 24 * 3600))
        for _ in 0..<105 { await store.append(record()) }
        let restarted = DiagnosticStore(file: file)
        let archive = await restarted.snapshot()
        XCTAssertEqual(archive.sessions.count, 100)
        XCTAssertTrue(archive.sessions.allSatisfy { Date().timeIntervalSince($0.finished) < 60 })
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertLessThanOrEqual((attributes[.size] as? Int) ?? .max, DiagnosticStore.maximumBytes)
        XCTAssertEqual((attributes[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? Int).map { $0 & 0o777 }, 0o700)
        try await restarted.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let empty = await restarted.snapshot()
        XCTAssertTrue(empty.sessions.isEmpty)
    }

    func testCorruptAndOversizedFilesArePreservedUntilExplicitClear() async throws {
        for original in [Data("not JSON".utf8), Data(repeating: 32, count: DiagnosticStore.maximumBytes + 1)] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: file) }
            try original.write(to: file)
            let store = DiagnosticStore(file: file)
            await store.append(record())
            let failed = await store.storageFailed
            XCTAssertTrue(failed)
            XCTAssertEqual(try Data(contentsOf: file), original)
            do { _ = try await store.export(); XCTFail("must report unreadable storage") } catch {}
            try await store.clear()
            await store.append(record())
            let recovered = await store.storageFailed
            XCTAssertFalse(recovered)
            let recoveredArchive = await store.snapshot()
            XCTAssertEqual(recoveredArchive.sessions.count, 1)
        }
    }

    func testTraceFinishesOnceAndRejectsLateEvents() throws {
        let trace = DiagnosticTrace(record: record())
        let span = trace.begin(.voiceInference)
        trace.cache(.cold)
        trace.interruption()
        trace.end(span, outcome: .cancelled)
        let finished = try XCTUnwrap(trace.finish(.cancelled, delivery: .none))
        XCTAssertEqual(finished.outcome, .cancelled)
        XCTAssertTrue(finished.interrupted)
        XCTAssertEqual(finished.voiceCache, .cold)
        XCTAssertEqual(finished.spans.filter { $0.stage == .voiceInference }.first?.outcome, .cancelled)
        trace.duration(.writingCleanup, milliseconds: 100)
        trace.end(span)
        XCTAssertNil(trace.finish(.completed, delivery: .pasted))
    }

    func testSamplesAndSpansAreBoundedAndInvalidDurationsAreRejected() throws {
        let trace = DiagnosticTrace(record: record())
        trace.duration(.voiceInference, milliseconds: .nan)
        trace.duration(.voiceInference, milliseconds: -.infinity)
        for _ in 0..<200 { trace.duration(.voiceInference, milliseconds: 1); trace.sample() }
        let result = try XCTUnwrap(trace.finish(.completed, delivery: .copied))
        XCTAssertLessThanOrEqual(result.spans.count, 64)
        XCTAssertLessThanOrEqual(result.resources.count, 128)
        XCTAssertTrue(result.truncated)
        XCTAssertTrue(result.spans.allSatisfy { $0.milliseconds.isFinite && $0.milliseconds >= 0 })
    }

    func testMalformedOptionalMetricsCannotDiscardASuccessfulTranscript() throws {
        let old = Data(#"{"success":true,"text":"Recognized words"}"#.utf8)
        let malformed = Data(#"{"success":true,"text":"Recognized words","diagnostics":{"cache":"future"}}"#.utf8)
        for data in [old, malformed] {
            let transcription = try JSONDecoder().decode(MLRPCResult.Transcribe.self, from: data)
            let correction = try JSONDecoder().decode(MLRPCResult.Correct.self, from: data)
            XCTAssertEqual(transcription.text, "Recognized words")
            XCTAssertEqual(correction.text, "Recognized words")
            XCTAssertNil(transcription.diagnostics)
            XCTAssertNil(correction.diagnostics)
        }
    }

    func testWorkerMetadataHasDistinctCPUAndMemorySemantics() throws {
        let trace = DiagnosticTrace(record: record())
        DiagnosticInstrumentation.$trace.withValue(trace) {
            DiagnosticWorkerMetrics(cache: .cold, loadMilliseconds: 30, operationMilliseconds: 50,
                                    cpuSeconds: 0.1, peakResidentBytes: 100).record(writing: false)
        }
        let result = try XCTUnwrap(trace.finish(.completed, delivery: .copied))
        let worker = try XCTUnwrap(result.resources.first { $0.scope == .modelWorker })
        XCTAssertFalse(worker.cpuIsCumulative)
        XCTAssertTrue(worker.memoryIsPeak)
        XCTAssertEqual(result.voiceCache, .cold)
        XCTAssertEqual(result.spans.first { $0.stage == .voiceModelLoad }?.milliseconds, 30)
    }

    func testSummaryUsesPerSessionStageTotalsAndExcludesFailedSpans() {
        var first = record(), second = record()
        first.spans = [.init(stage: .voiceInference, milliseconds: 20, outcome: .completed),
                       .init(stage: .voiceInference, milliseconds: 10, outcome: .completed)]
        second.spans = [.init(stage: .voiceInference, milliseconds: 100, outcome: .completed),
                        .init(stage: .voiceInference, milliseconds: 999, outcome: .failed)]
        let summary = DiagnosticSummary([first, second])
        XCTAssertEqual(summary.stages[.voiceInference]?.median, 30)
        XCTAssertEqual(summary.stages[.voiceInference]?.p95, 100)
    }

    func testMetadataSchemaCannotSerializeTranscriptionInputs() async throws {
        XCTAssertNil(DiagnosticRecord.modelIdentifier("/Users/private/audio.wav"))
        XCTAssertNil(DiagnosticRecord.modelIdentifier("../../../secret"))
        XCTAssertNil(DiagnosticRecord.modelIdentifier("private transcript with spaces"))
        XCTAssertEqual(DiagnosticRecord.modelIdentifier("mlx-community/model-4bit"), "mlx-community/model-4bit")
        let store = DiagnosticStore(file: nil)
        await store.append(record())
        let exported = try await store.export()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: exported) as? [String: Any])
        let sessions = try XCTUnwrap(object["sessions"] as? [[String: Any]])
        let allowed: Set<String> = ["id", "started", "finished", "build", "system", "architecture", "entry", "provider",
                                    "voiceModel", "preferredInput", "outcome", "delivery", "voiceCache", "writingCache",
                                    "truncated", "interrupted", "spans", "resources"]
        XCTAssertEqual(Set(try XCTUnwrap(sessions.first).keys), allowed)
    }
}
