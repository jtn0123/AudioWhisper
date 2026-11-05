import XCTest
@testable import AudioWhisper

@MainActor
final class PublicAutomationTests: IsolatedXCTestCase {
    func testAutomationPreflightDoesNotCreateAnAbsentPythonProject() async throws {
        let key = "AUDIOWHISPER_APP_SUPPORT_DIR"
        let previous = ProcessInfo.processInfo.environment[key]
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        setenv(key, root.path, 1)
        defer {
            if let previous { setenv(key, previous, 1) } else { unsetenv(key) }
            try? FileManager.default.removeItem(at: root)
        }
        let services = PublicAutomationServices.live
        let local = await services.runtimeReady(.init(provider: .local, whisper: .base, parakeet: .v2English))
        let python = await services.runtimeReady(.init(provider: .parakeet, whisper: .base, parakeet: .v2English))
        XCTAssertTrue(local)
        XCTAssertFalse(python)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testMCPRejectsMalformedRequestsAndReturnsExplicitToolOutcomes() async throws {
        var responses: [[String: Any]] = []
        let finished = expectation(description: "Status and inference publish their outcomes")
        finished.expectedFulfillmentCount = 2
        let server = PublicMCPServer(directory: URL(fileURLWithPath: "/allowed"), write: { data in
            guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            responses.append(value)
            if [99, 100].contains(value["id"] as? Int ?? -1) { finished.fulfill() }
        }, transcribe: { _, _, _ in throw PublicAutomationError.assets }, status: { Data("{}".utf8) })
        server.receive(Data("invalid json".utf8))
        XCTAssertEqual((responses.last?["error"] as? [String: Any])?["code"] as? Int, -32700)
        for raw in ["{\"jsonrpc\":\"1.0\",\"id\":true,\"method\":\"ping\"}",
                    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":[]}"] {
            server.receive(Data(raw.utf8))
            XCTAssertNotNil(responses.last?["error"])
        }
        func send(_ method: String, id: Int? = nil, params: [String: Any] = [:]) throws {
            var request: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
            if let id { request["id"] = id }
            server.receive(try JSONSerialization.data(withJSONObject: request))
        }
        try send("initialize", id: 1, params: ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": [:]])
        try send("notifications/initialized")
        for params in [["name": 3], ["name": "transcribe_file", "arguments": ["path": "x", "modeID": "invalid"]]] {
            try send("tools/call", id: 2, params: params)
            XCTAssertNotNil(responses.last?["error"])
        }
        try send("tools/call", id: 99, params: ["name": "status"])
        try send("tools/call", id: 100, params: ["name": "transcribe_file", "arguments": ["path": "/allowed/clip.wav"]])
        await fulfillment(of: [finished], timeout: 5)
        let status = responses.first { ($0["id"] as? Int) == 99 }?["result"] as? [String: Any]
        let failed = responses.first { ($0["id"] as? Int) == 100 }?["result"] as? [String: Any]
        XCTAssertEqual(status?["isError"] as? Bool, false)
        XCTAssertEqual(failed?["isError"] as? Bool, true)
        await server.oversized()
        XCTAssertEqual((responses.last?["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testFileTranscriptionSnapshotsModeDisablesContextAndReportsWritingOutcome() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try Data([1]).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        var settings = AppDefaults.currentDictationSettings
        settings.writing.contextSource = .clipboard
        settings.language = .japanese
        let mode = try SavedDictationMode.make(name: "Automation", settings: settings, existing: [])
        AppDefaults.savedDictationModes = [mode]
        var outcome: CorrectionOutcome?
        let services = PublicAutomationServices(
            runtimeReady: { _ in true }, modelInstalled: { _ in true }, transcribe: { url, captured in
            XCTAssertEqual(url, file)
            XCTAssertEqual(captured.writing.contextSource, .none)
            XCTAssertEqual(captured.language, .japanese)
            return .init(text: "Final", correctionOutcome: outcome, originalText: "Original", audioDuration: 2)
        })
        let cases: [(CorrectionOutcome?, String)] = [
            (nil, "off"), (.applied("Final"), "applied"),
            (.rejected("Original"), "rejected_original_preserved"),
            (.failed(PublicAutomationError.assets, fallback: "Original"), "unavailable_original_preserved")
        ]
        for (value, expected) in cases {
            outcome = value
            let result = try await PublicAutomation.transcribe(path: file.path, modeID: mode.id, services: services)
            XCTAssertEqual(result.writingOutcome, expected)
            XCTAssertEqual(result.originalText, "Original")
            XCTAssertEqual(result.audioDuration, 2)
        }
        XCTAssertEqual(AppDefaults.savedDictationModes, [mode], "Automation must not persist its consent-free snapshot")
        do {
            _ = try await PublicAutomation.transcribe(path: file.path, modeID: UUID(), services: services)
            XCTFail("Unknown modes must fail before inference")
        } catch { XCTAssertEqual(error as? PublicAutomationError, .mode) }
        var unavailable = services
        unavailable.runtimeReady = { _ in false }
        do {
            _ = try await PublicAutomation.transcribe(path: file.path, modeID: nil, services: unavailable)
            XCTFail("Automation must not install missing assets")
        } catch { XCTAssertEqual(error as? PublicAutomationError, .assets) }
    }

    func testInstalledInferencePreservesWorkerResultAndPropagatesFailure() async throws {
        var settings = AppDefaults.currentDictationSettings
        settings.provider = .local
        settings.cleanup = .off
        let pipeline = AutomationPipelineFixture()
        let result = try await PublicAutomation.installedTranscription(
            URL(fileURLWithPath: "/fixture.wav"), settings: settings, pipeline: pipeline)
        XCTAssertEqual(result.text, "Local result")
        pipeline.fail = true
        do {
            _ = try await PublicAutomation.installedTranscription(
                URL(fileURLWithPath: "/fixture.wav"), settings: settings, pipeline: pipeline)
            XCTFail("Pipeline errors must not become empty successes")
        } catch { XCTAssertEqual(error as? PublicAutomationError, .file) }
    }

    func testAutomationDaemonCannotPrepareAnUnconfiguredRuntime() async throws {
        let daemon = MLDaemonManager(allowsRuntimePreparation: false)
        do {
            _ = try await daemon.resolvedPython()
            XCTFail("Automation must not prepare a runtime implicitly")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Installed local runtime required"))
        }
        await daemon.shutdown()
    }

    func testRealExecutableKeepsStdoutAsNewlineDelimitedMCPOnly() async throws {
        let executable = Bundle(for: Self.self).bundleURL.deletingLastPathComponent().appendingPathComponent("AudioWhisper")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            XCTFail("The current test products must include the app executable: \(executable.path)")
            return
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["mcp", "--allow-directory", FileManager.default.temporaryDirectory.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = expectation(description: "MCP closes on stdin EOF")
        process.terminationHandler = { _ in finished.fulfill() }
        try process.run()
        let messages: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": "init", "method": "initialize",
             "params": ["protocolVersion": "2025-11-25", "capabilities": [:], "clientInfo": ["name": "test", "version": "1"]]],
            ["jsonrpc": "2.0", "method": "notifications/initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list"],
            ["jsonrpc": "2.0", "id": 3, "method": "ping"]
        ]
        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0a)
            input.fileHandleForWriting.write(data)
        }
        try input.fileHandleForWriting.close()
        await fulfillment(of: [finished], timeout: 5)
        if process.isRunning { process.terminate() }
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let lines = try XCTUnwrap(String(data: bytes, encoding: .utf8)).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
        for line in lines {
            let message = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            XCTAssertEqual(message["jsonrpc"] as? String, "2.0")
            XCTAssertNotNil(message["result"])
        }
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testCommandsRejectAmbiguousArgumentsAndKeepTranscriptionExplicit() throws {
        let id = UUID()
        XCTAssertEqual(try AutomationCommand.parse([]), nil)
        XCTAssertEqual(try AutomationCommand.parse(["transcribe", "/clip.wav", "--mode", id.uuidString, "--json"]),
                       .transcribe(path: "/clip.wav", mode: id, json: true))
        for arguments in [["record"], ["mcp"], ["transcribe"], ["transcribe", "/clip.wav", "--paste"],
                          ["status", "extra"], ["transcribe", "/clip.wav", "--json", "--json"]] {
            XCTAssertThrowsError(try AutomationCommand.parse(arguments))
        }
    }

    func testDeepLinksOnlyNavigateAndRejectHiddenActions() throws {
        XCTAssertEqual(RebuildDeepLink.page(try XCTUnwrap(URL(string: "audiowhisper://open?page=library"))), .library)
        for raw in ["audiowhisper://record", "audiowhisper://open?page=record&start=true",
                    "audiowhisper://open?page=record&page=library", "https://open?page=library"] {
            XCTAssertNil(RebuildDeepLink.page(try XCTUnwrap(URL(string: raw))))
        }
    }

    func testAllowedDirectoryRejectsTraversalAndSymlinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let allowed = root.appendingPathComponent("allowed", isDirectory: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("outside.wav")
        try Data([1]).write(to: outside)
        let link = allowed.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let canonical = try PublicAutomation.directory(allowed.path)
        XCTAssertThrowsError(try PublicAutomation.audioURL(path: link.path, allowedDirectory: canonical))
        XCTAssertThrowsError(try PublicAutomation.audioURL(path: allowed.path + "/../outside.wav", allowedDirectory: canonical))
        XCTAssertThrowsError(try PublicAutomation.directory("/"))
    }

    func testMCPNegotiatesListsToolsAndKeepsReaderResponsiveDuringInference() async throws {
        var replies: [[String: Any]] = []
        var release: CheckedContinuation<Void, Never>?
        let server = PublicMCPServer(directory: URL(fileURLWithPath: "/allowed"), write: {
            if let object = try? JSONSerialization.jsonObject(with: $0) as? [String: Any] { replies.append(object) }
        }, transcribe: { path, _, _ in
            XCTAssertEqual(path, "/allowed/clip.wav")
            await withCheckedContinuation { release = $0 }
            return PublicTranscription(text: "Recognized words", originalText: "Recognized words",
                                       writingOutcome: "off", audioDuration: 1)
        }, status: { Data("{}".utf8) })
        func send(_ method: String, id: Any? = nil, params: [String: Any] = [:]) throws {
            var message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
            if let id { message["id"] = id }
            server.receive(try JSONSerialization.data(withJSONObject: message))
        }
        try send("tools/list", id: 0)
        XCTAssertNotNil(replies.last?["error"])
        try send("initialize", id: "init", params: ["protocolVersion": "2099-01-01", "capabilities": [:], "clientInfo": [:]])
        let initialization = try XCTUnwrap(replies.last?["result"] as? [String: Any])
        XCTAssertEqual(initialization["protocolVersion"] as? String, "2025-11-25")
        try send("notifications/initialized")
        try send("tools/list", id: 1)
        let tools = (replies.last?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 2)
        try send("tools/call", id: 2, params: ["name": "transcribe_file", "arguments": ["path": "/allowed/clip.wav"]])
        for _ in 0..<100 where release == nil { await Task.yield() }
        XCTAssertNotNil(release)
        try send("ping", id: "responsive")
        XCTAssertEqual(replies.last?["id"] as? String, "responsive")
        try send("tools/call", id: 3, params: ["name": "transcribe_file", "arguments": ["path": "/allowed/other.wav"]])
        XCTAssertEqual((replies.last?["result"] as? [String: Any])?["isError"] as? Bool, true)
        try send("notifications/cancelled", params: ["requestId": 2])
        try send("tools/call", id: 4, params: ["name": "transcribe_file", "arguments": ["path": "/allowed/new.wav"]])
        XCTAssertEqual((replies.last?["result"] as? [String: Any])?["isError"] as? Bool, true,
                       "Cancellation must not release capacity before the actual worker finishes")
        release?.resume()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(replies.contains { ($0["id"] as? Int) == 2 }, "Cancelled inference must not publish stale output")
        await server.shutdown()
    }
}

@MainActor
private final class AutomationPipelineFixture: TranscriptionPipeline {
    var fail = false
    override func transcribe(audioURL: URL, config: TranscriptionPipelineConfig) async throws -> TranscriptionResult {
        if fail { throw PublicAutomationError.file }
        return .init(text: "Local result", correctionOutcome: nil)
    }
}
