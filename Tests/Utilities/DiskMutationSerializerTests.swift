import XCTest
@testable import AudioWhisper

final class DiskMutationSerializerTests: XCTestCase {

    // MARK: - Serializer

    func test_serializer_runsSequentialCallsOnSameKey() async throws {
        let serializer = DiskMutationSerializer<String>()
        let counter = Counter()

        try await serializer.run(key: "alpha") {
            await counter.increment()
        }
        try await serializer.run(key: "alpha") {
            await counter.increment()
        }
        try await serializer.run(key: "alpha") {
            await counter.increment()
        }

        let final = await counter.value
        XCTAssertEqual(final, 3)
    }

    func test_serializer_concurrentSameKeyCallersShareTask() async throws {
        // Two concurrent callers for the same key should share one in-flight
        // task: the body runs exactly once.
        let serializer = DiskMutationSerializer<String>()
        let counter = Counter()

        async let firstRun: Void = try serializer.run(key: "shared") {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await counter.increment()
        }
        async let secondRun: Void = try serializer.run(key: "shared") {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await counter.increment()
        }

        _ = try await (firstRun, secondRun)
        let final = await counter.value
        XCTAssertEqual(final, 1, "Concurrent same-key callers should run the body exactly once")
    }

    func test_serializer_differentKeysRunInParallel() async throws {
        // Different keys must not block each other. Proven deterministically
        // rather than with a wall-clock threshold (which is flaky on loaded
        // CI runners): both operation bodies must be able to sit inside run()
        // at the same time. If the serializer wrongly serialized different
        // keys, only one body could be inside at once, `inside` would never
        // reach 2, and the safety cap below would fail the test.
        let serializer = DiskMutationSerializer<String>()
        let counter = Counter()
        let inside = Counter()
        let release = Latch()

        async let firstRun: Void = try serializer.run(key: "one") {
            await inside.increment()
            await release.wait()
            await counter.increment()
        }
        async let secondRun: Void = try serializer.run(key: "two") {
            await inside.increment()
            await release.wait()
            await counter.increment()
        }

        // Wait until both bodies are concurrently inside run().
        var waitedMs = 0
        while await inside.value < 2 {
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            waitedMs += 5
            if waitedMs > 5_000 {
                await release.open()
                _ = try? await (firstRun, secondRun)
                XCTFail("Different-keyed callers did not run in parallel")
                return
            }
        }
        await release.open()
        _ = try await (firstRun, secondRun)
        let final = await counter.value
        XCTAssertEqual(final, 2)
    }

    func test_serializer_propagatesErrors() async {
        let serializer = DiskMutationSerializer<String>()
        do {
            try await serializer.run(key: "boom") {
                throw NSError(domain: "TestError", code: 42)
            }
            XCTFail("Expected error to be propagated")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "TestError")
            XCTAssertEqual(error.code, 42)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func test_serializer_failedOpIsNotCachedForNextCaller() async throws {
        // Bug #39: a failed operation must NOT linger in `inFlight` and be
        // re-served to the next caller. After a failure, a fresh call with the
        // same key must run a brand-new op (which can succeed).
        let serializer = DiskMutationSerializer<String>()
        let attempts = Counter()

        do {
            try await serializer.run(key: "retry") {
                await attempts.increment()
                throw NSError(domain: "FirstAttempt", code: 1)
            }
            XCTFail("First attempt should have thrown")
        } catch {
            // expected
        }

        // Immediately retry — no sleep — so we exercise the window where the
        // old detached-clear implementation would still serve the failed task.
        try await serializer.run(key: "retry") {
            await attempts.increment()
        }

        let total = await attempts.value
        XCTAssertEqual(total, 2, "Retry after failure must run a fresh op, not reuse the failed one")
    }

    func test_serializer_clearsKeyAfterCompletion() async throws {
        // After an operation completes, a new call with the same key
        // should start a fresh task (not reuse the previous result).
        let serializer = DiskMutationSerializer<String>()
        let counter = Counter()

        try await serializer.run(key: "x") { await counter.increment() }
        // Give the deferred clear() a moment to run.
        try await Task.sleep(nanoseconds: 20_000_000)
        try await serializer.run(key: "x") { await counter.increment() }

        let final = await counter.value
        XCTAssertEqual(final, 2)
    }

    // MARK: - ModelIntegrity

    func test_modelIntegrity_recordAndVerifyRoundTrip() throws {
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        try Data([0x01, 0x02, 0x03, 0x04]).write(to: modelURL)

        try ModelIntegrity.record(at: modelURL)

        // Verify succeeds against a matching file.
        XCTAssertNoThrow(try ModelIntegrity.verify(at: modelURL))
    }

    /// Audit item E3. The recorded hash must NOT live beside the model it
    /// vouches for: anything able to rewrite the model in that directory could
    /// rewrite the hash too, and the check would pass. This test is the point
    /// of E3 — it fails if the record moves back in-place.
    func test_modelIntegrity_recordIsNotStoredBesideTheModel() throws {
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        try Data([0x01, 0x02, 0x03, 0x04]).write(to: modelURL)

        try ModelIntegrity.record(at: modelURL)

        let inPlace = modelURL.appendingPathExtension("audiowhisper-integrity")
        XCTAssertFalse(FileManager.default.fileExists(atPath: inPlace.path),
                       "integrity record must not be written into the model's own directory")

        let siblings = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertEqual(siblings, ["model.bin"],
                       "the model directory must contain only the model, got \(siblings)")
    }

    /// A pre-E3 cache still has its hash beside the model. That must keep
    /// verifying rather than forcing a multi-gigabyte redownload.
    func test_modelIntegrity_readsLegacyInPlaceSidecar() throws {
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        let bytes = Data([0x07, 0x08])
        try bytes.write(to: modelURL)

        // Hand-write a legacy sidecar holding the correct hash, as an old
        // install would have left behind.
        let legacy = modelURL.appendingPathExtension("audiowhisper-integrity")
        try ModelIntegrity.sha256(of: modelURL).write(to: legacy, atomically: true, encoding: .utf8)

        XCTAssertNoThrow(try ModelIntegrity.verify(at: modelURL),
                         "a legacy in-place sidecar must still be honoured")
    }

    /// And a legacy sidecar must still catch tampering, not just pass.
    func test_modelIntegrity_legacySidecarStillDetectsTamper() throws {
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        try Data([0x07, 0x08]).write(to: modelURL)

        let legacy = modelURL.appendingPathExtension("audiowhisper-integrity")
        try ModelIntegrity.sha256(of: modelURL).write(to: legacy, atomically: true, encoding: .utf8)

        try Data([0xDE, 0xAD]).write(to: modelURL)

        XCTAssertThrowsError(try ModelIntegrity.verify(at: modelURL)) { error in
            guard case ModelIntegrityError.mismatch = error else {
                return XCTFail("Expected .mismatch, got \(error)")
            }
        }
    }

    func test_modelIntegrity_detectsTamper() throws {
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        try Data([0x01, 0x02, 0x03, 0x04]).write(to: modelURL)

        try ModelIntegrity.record(at: modelURL)

        // Mutate the file contents.
        try Data([0x09, 0x09, 0x09, 0x09]).write(to: modelURL)

        XCTAssertThrowsError(try ModelIntegrity.verify(at: modelURL)) { error in
            guard case ModelIntegrityError.mismatch = error else {
                XCTFail("Expected ModelIntegrityError.mismatch, got \(error)")
                return
            }
        }
    }

    func test_modelIntegrity_trustOnFirstUseRecordsAndThenCompares() throws {
        // Nothing recorded yet → verify() should record and succeed.
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        try Data([0xAA, 0xBB]).write(to: modelURL)

        XCTAssertNoThrow(try ModelIntegrity.verify(at: modelURL))

        // Second verify compares against the persisted hash rather than
        // recording again — proved by tampering and expecting a mismatch.
        XCTAssertNoThrow(try ModelIntegrity.verify(at: modelURL))

        try Data([0xCC, 0xDD]).write(to: modelURL)
        XCTAssertThrowsError(try ModelIntegrity.verify(at: modelURL),
                             "the first-use hash must have been persisted")
    }

    func test_modelIntegrity_sha256IsStable() throws {
        // Same bytes → same hash, regardless of how many times we call.
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        let bytes = Data(repeating: 0x42, count: 200_000) // 200KB to exercise chunk loop
        try bytes.write(to: modelURL)

        let firstHash = try ModelIntegrity.sha256(of: modelURL)
        let secondHash = try ModelIntegrity.sha256(of: modelURL)
        XCTAssertEqual(firstHash, secondHash)
        XCTAssertEqual(firstHash.count, 64, "SHA-256 hex digest should be 64 chars")
    }

    func test_modelIntegrity_quietVerifyReturnsFalseOnMismatch() throws {
        let tmpDir = makeTempDir()
        let modelURL = tmpDir.appendingPathComponent("model.bin")
        try Data([0x01]).write(to: modelURL)
        try ModelIntegrity.record(at: modelURL)
        try Data([0x02]).write(to: modelURL)

        XCTAssertFalse(ModelIntegrity.quietVerify(at: modelURL))
    }

    // MARK: - Helpers

    private func makeTempDir() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DiskMutationSerializerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

/// Sendable counter for cross-task accumulation in tests.
private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}

/// One-shot latch: `wait()` suspends until someone calls `open()`.
private actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
