import XCTest
@testable import AudioWhisper

final class BundledPythonImmutabilityTests: XCTestCase {
    func testDaemonLeavesBundledResourcesUnchanged() async throws {
        let fileManager = FileManager.default
        let script = try XCTUnwrap(ResourceLocator.pythonScriptURL(named: "ml_daemon"))
        let resources = fileManager.temporaryDirectory
            .appendingPathComponent("sealed-python-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: resources) }
        try fileManager.copyItem(at: script, to: resources.appendingPathComponent("ml_daemon.py"))
        try fileManager.copyItem(
            at: script.deletingLastPathComponent().appendingPathComponent("ml"),
            to: resources.appendingPathComponent("ml"))
        // Development runs may already have caches; a signed build excludes them.
        let copiedFiles = try XCTUnwrap(fileManager.enumerator(atPath: resources.path)?.allObjects as? [String])
        for path in copiedFiles where path.hasSuffix("/__pycache__") {
            try fileManager.removeItem(at: resources.appendingPathComponent(path))
        }
        let before = Set(try XCTUnwrap(fileManager.enumerator(atPath: resources.path)?.allObjects as? [String]))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", resources.appendingPathComponent("ml_daemon.py").path]
        var environment = await MLDaemonManager.daemonEnvironment()
        environment.removeValue(forKey: "PYTHONPATH")
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\n".utf8))
        try input.fileHandleForWriting.close()
        let response = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try output.fileHandleForReading.close()
        XCTAssertEqual(process.terminationStatus, 0)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
        XCTAssertEqual((result["result"] as? [String: Bool])?["pong"], true)

        let after = Set(try XCTUnwrap(fileManager.enumerator(atPath: resources.path)?.allObjects as? [String]))
        XCTAssertEqual(after, before, "Python must not invalidate the app's sealed resources with bytecode caches")
    }
}
