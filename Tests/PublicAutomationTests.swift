import XCTest
@testable import AudioWhisper

@MainActor
final class PublicAutomationTests: IsolatedXCTestCase {
    func testRealExecutableKeepsStdoutAsNewlineDelimitedMCPOnly() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let executable = root.appendingPathComponent(".build/debug/AudioWhisper")
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
        release?.resume()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(replies.contains { ($0["id"] as? Int) == 2 }, "Cancelled inference must not publish stale output")
        server.shutdown()
    }
}
