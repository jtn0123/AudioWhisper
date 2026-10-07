import XCTest
@testable import AudioWhisper

@MainActor
final class WritingInstallCancellationTests: IsolatedXCTestCase {
    func testCancelStopsTheActualProcessReleasesMaintenanceAndKeepsPartialFiles() async throws {
        try await exerciseCancelAndRetry()
    }

    private func exerciseCancelAndRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let partial = directory.appendingPathComponent("weights.partial")
        var process: Process?
        let manager = MLXModelManager(
            cacheDirectory: directory,
            prepareDownloadPython: { URL(fileURLWithPath: "/usr/bin/python3") },
            downloadProcessFactory: { _, _ in
                let created = Process()
                created.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                created.arguments = ["-c", "import json,time,pathlib,sys; "
                    + "pathlib.Path(sys.argv[1]).write_text('partial'); "
                    + "print(json.dumps({'status':'downloading','message':'half downloaded',"
                    + "'completed':5,'total':10}),flush=True); "
                    + "time.sleep(30)", partial.path]
                process = created
                return created
            })
        let installer = RebuildWritingInstaller(manager: manager)
        let session = RebuildSession(services: .live(recorder: AudioEngineRecorder()))
        installer.start("fixture/model", session: session)
        for _ in 0..<200 where installer.fraction == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(installer.fraction, 0.5)
        XCTAssertTrue(session.maintenanceInProgress)
        await installer.cancel()
        XCTAssertFalse(try XCTUnwrap(process).isRunning)
        XCTAssertFalse(session.maintenanceInProgress)
        XCTAssertFalse(installer.isRunning)
        XCTAssertTrue(installer.status?.hasPrefix("Cancelled") == true)
        XCTAssertEqual(installer.status(for: "fixture/model"), installer.status)
        XCTAssertNil(installer.status(for: "fixture/other-model"), "A terminal result belongs only to its installed model")
        XCTAssertEqual(try String(contentsOf: partial, encoding: .utf8), "partial")
        // Retry must create a fresh process rather than retain a cancelled operation.
        installer.start("fixture/model", session: session)
        XCTAssertNil(installer.status(for: "fixture/model"), "A retry clears the previous terminal result")
        for _ in 0..<200 where manager.activeDownloads["fixture/model"] == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        await installer.cancel()
        XCTAssertFalse(session.maintenanceInProgress)
    }

    func testSplitUTF8AndJSONEventsRetainTheActualError() {
        let buffer = DownloadOutputBuffer()
        let text = #"{"status":"error","message":"Connection lost — retry"}"# + "\n"
        let bytes = Data(text.utf8)
        var lines: [String] = []
        for byte in bytes { lines += buffer.append(Data([byte])) }
        XCTAssertEqual(lines, [String(text.dropLast())])
        XCTAssertEqual(buffer.error, "Connection lost — retry")
    }

    func testPrelaunchCancellationClosesPipesWithoutStartingProcess() async {
        let manager = MLXModelManager(cacheDirectory: FileManager.default.temporaryDirectory)
        let output = Pipe()
        let errors = Pipe()
        output.fileHandleForReading.readabilityHandler = { _ in }
        errors.fileHandleForReading.readabilityHandler = { _ in }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let job = Task {
            try? await Task.sleep(for: .seconds(1))
            await manager.runDownloadProcess(process, repo: "fixture/cancel", outputPipe: output, errorPipe: errors)
        }
        job.cancel()
        await job.value
        XCTAssertFalse(process.isRunning)
        XCTAssertNil(output.fileHandleForReading.readabilityHandler)
        XCTAssertNil(errors.fileHandleForReading.readabilityHandler)
        XCTAssertThrowsError(try output.fileHandleForReading.read(upToCount: 1))
        XCTAssertThrowsError(try errors.fileHandleForReading.read(upToCount: 1))
    }

    func testInstantProcessFailuresPreserveTheActionableError() async {
        let manager = MLXModelManager(
            cacheDirectory: FileManager.default.temporaryDirectory,
            prepareDownloadPython: { URL(fileURLWithPath: "/usr/bin/python3") },
            downloadProcessFactory: { _, _ in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
                process.arguments = ["-c", "import json,sys; "
                    + "print(json.dumps({'status':'error','message':'Connection lost: retry'}),flush=True); sys.exit(1)"]
                return process
            })
        for _ in 0..<20 {
            await manager.downloadModel("fixture/error")
            XCTAssertEqual(manager.downloadProgress["fixture/error"], "Error: Connection lost: retry")
        }
    }

}
