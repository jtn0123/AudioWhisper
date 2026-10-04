import XCTest
@testable import AudioWhisper

final class DaemonTransportReliabilityTests: XCTestCase {
    private var manager: MLDaemonManager!
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        manager = MLDaemonManager()
        let script = directory.appendingPathComponent("daemon.py")
        try """
        import json, sys, time, pathlib
        root = pathlib.Path(__file__).parent
        for line in sys.stdin:
            try:
                request = json.loads(line)
            except Exception:
                sys.exit(7)
            params = request.get('params') or {}
            if params.get('repo') == 'blocked':
                (root / 'arrived').touch()
                while not (root / 'release').exists():
                    time.sleep(0.01)
            if request['method'] == 'transcribe':
                text = pathlib.Path(params['pcm_path']).read_text()
            else:
                text = params.get('text', '')
            result = {'success': True, 'text': text, 'pong': True}
            print(json.dumps({'id': request['id'], 'result': result}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        await manager.setTestOverrides(python: URL(fileURLWithPath: "/usr/bin/python3"), script: script)
    }

    override func tearDown() async throws {
        FileManager.default.createFile(atPath: directory.appendingPathComponent("release").path, contents: Data())
        await manager.shutdown()
        try? FileManager.default.removeItem(at: directory)
    }

    func testConcurrentLargeFramesRemainSeparateAndMappedToTheirCallers() async throws {
        let manager = try XCTUnwrap(manager)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<12 {
                group.addTask {
                    let text = "request-\(index) " + String(repeating: String(index % 10), count: 160_000)
                    let output = try await manager.correct(repo: "test", text: text, prompt: nil)
                    XCTAssertEqual(output, text)
                }
            }
            try await group.waitForAll()
        }
        let count = await manager.pendingCountForTesting()
        XCTAssertEqual(count, 0)
    }

    func testCanceledTranscriptionKeepsPCMUntilWorkerActuallyFinishes() async throws {
        let pcm = directory.appendingPathComponent("audio.raw")
        try "leased audio".write(to: pcm, atomically: true, encoding: .utf8)
        let service = ParakeetService(daemon: manager)
        let task = Task { try await service.transcribePreparedPCM(pcm, repo: "blocked") }
        let arrived = directory.appendingPathComponent("arrived")
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: arrived.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: arrived.path))
        task.cancel()
        do { _ = try await task.value; XCTFail("expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: pcm.path), "worker still owns its audio")
        FileManager.default.createFile(atPath: directory.appendingPathComponent("release").path, contents: Data())
        let cleanupDeadline = ContinuousClock.now + .seconds(3)
        while FileManager.default.fileExists(atPath: pcm.path), ContinuousClock.now < cleanupDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: pcm.path))
        let pending = await manager.pendingCountForTesting()
        XCTAssertEqual(pending, 0)
    }

    func testWarmupCancellationFinishesBeforeDaemonResponds() async throws {
        let manager = try XCTUnwrap(manager)
        let task = Task { try await manager.warmup(type: .mlx, repo: "blocked") }
        let arrived = directory.appendingPathComponent("arrived")
        let deadline = ContinuousClock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: arrived.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: arrived.path))
        let finished = expectation(description: "canceled caller released")
        task.cancel()
        Task {
            do { try await task.value; XCTFail("expected cancellation") }
            catch { XCTAssertTrue(error is CancellationError) }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 1)
        FileManager.default.createFile(atPath: directory.appendingPathComponent("release").path, contents: Data())
        _ = try? await task.value
    }
}
