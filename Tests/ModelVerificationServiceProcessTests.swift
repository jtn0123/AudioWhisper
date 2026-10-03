import XCTest
@testable import AudioWhisper

/// Tests for `ModelVerificationService.verify`, the process plumbing around the
/// output parsing that `ModelVerificationServiceTests` covers.
///
/// The interpreter is a bash script standing in for the venv python: it is
/// handed the real bundled script path and the arguments, and prints whatever
/// the case needs. That exercises argument construction, both pipes, the exit
/// status mapping and the timeout without a Python environment or a model.
final class ModelVerificationServiceProcessTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelVerificationProcessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testSuccessReportsTheLastStdoutMessage() async throws {
        let python = try fakePython("""
            echo '{"message": "Loading weights"}'
            echo 'progress bar noise' >&2
            echo '{"message": "Model verified"}'
            exit 0
            """)

        let result = try await verify(python: python)

        XCTAssertEqual(result, ModelVerificationResult(succeeded: true, message: "Model verified"))
    }

    func testSuccessWithNoMessageUsesTheFallback() async throws {
        let result = try await verify(python: try fakePython("exit 0"))
        XCTAssertEqual(result, ModelVerificationResult(succeeded: true, message: "fallback"))
    }

    func testTheScriptAndArgumentsArePassedAsArgv() async throws {
        let argsFile = tempDir.appendingPathComponent("args.txt")
        let python = try fakePython("""
            printf '%s\\n' "$@" > '\(argsFile.path)'
            exit 0
            """)

        _ = try await verify(python: python, arguments: ["org/model; rm -rf ~", "--flag"])

        let argv = try String(contentsOf: argsFile, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertEqual(argv.count, 3)
        XCTAssertTrue(argv[0].hasSuffix("verify_parakeet.py"), argv[0])
        // A hostile-looking repo arrives as one untouched argument.
        XCTAssertEqual(Array(argv.dropFirst()), ["org/model; rm -rf ~", "--flag"])
    }

    func testFailurePrefersTheStdoutMessage() async throws {
        let python = try fakePython("""
            echo '{"message": "Repository not found"}'
            echo 'Traceback ...' >&2
            exit 1
            """)

        let result = try await verify(python: python)

        XCTAssertEqual(
            result,
            ModelVerificationResult(succeeded: false, message: "Verification failed: Repository not found")
        )
    }

    func testFailureFallsBackToStderr() async throws {
        let python = try fakePython("""
            echo 'ModuleNotFoundError: No module named parakeet_mlx' >&2
            exit 2
            """)

        let result = try await verify(python: python)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, "Verification failed: ModuleNotFoundError: No module named parakeet_mlx")
    }

    /// The timeout exists so the Settings UI cannot spin forever on a hung
    /// verify. A terminated run is a failure, not a success.
    func testAHungScriptIsTerminatedAtTheTimeout() async throws {
        let python = try fakePython("exec /bin/sleep 30")
        let start = ContinuousClock.now

        let result = try await verify(python: python, timeout: .milliseconds(300))

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, "Verification failed")
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(10), "verify must not wait out the script")
    }

    func testAMissingScriptThrowsScriptNotFound() async {
        do {
            _ = try await ModelVerificationService.verify(
                scriptName: "no_such_script_\(UUID().uuidString)",
                arguments: [],
                pythonPath: "/usr/bin/true",
                successFallback: "fallback"
            )
            XCTFail("expected scriptNotFound")
        } catch let error as ModelVerificationError {
            guard case .scriptNotFound(let name) = error else { return XCTFail("got \(error)") }
            XCTAssertTrue(name.hasPrefix("no_such_script_"))
            XCTAssertEqual(error.errorDescription, "Script not found: \(name)")
        } catch {
            XCTFail("expected ModelVerificationError, got \(error)")
        }
    }

    func testAMissingInterpreterThrows() async {
        do {
            _ = try await verify(python: tempDir.appendingPathComponent("no-python").path)
            XCTFail("expected Process.run() to throw")
        } catch {
            XCTAssertFalse(error is ModelVerificationError, "the script exists; launching is what fails")
        }
    }

    // MARK: - Helpers

    private func verify(
        python: String,
        arguments: [String] = ["org/model"],
        timeout: Duration = .seconds(30)
    ) async throws -> ModelVerificationResult {
        try await ModelVerificationService.verify(
            scriptName: "verify_parakeet",
            arguments: arguments,
            pythonPath: python,
            successFallback: "fallback",
            timeout: timeout
        )
    }

    private func fakePython(_ body: String) throws -> String {
        let url = tempDir.appendingPathComponent("python-\(UUID().uuidString)")
        try Data("#!/bin/bash\n\(body)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }
}
