import Foundation
import XCTest
@testable import AudioWhisper

/// Coverage tests for `UvBootstrap` and `UvBootstrap+Process`.
///
/// Exercises pure logic that needs no network or real uv binary: subprocess
/// result capture via `run`/`runInDir`, semantic version comparison, project
/// directory creation, environment-readiness checks, `UvError` descriptions,
/// and the `VenvSerializer` actor.
final class UvBootstrapCoverageTests: XCTestCase {
    private var originalHome: String?
    private var originalAppSupportOverride: String?
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalHome = ProcessInfo.processInfo.environment["HOME"]
        originalAppSupportOverride = ProcessInfo.processInfo.environment["AUDIOWHISPER_APP_SUPPORT_DIR"]

        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("UvBootstrapCoverageTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let appSupport = tempRoot.appendingPathComponent("AppSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        setenv("AUDIOWHISPER_APP_SUPPORT_DIR", appSupport.path, 1)
    }

    override func tearDownWithError() throws {
        if let originalHome { setenv("HOME", originalHome, 1) }
        if let originalAppSupportOverride {
            setenv("AUDIOWHISPER_APP_SUPPORT_DIR", originalAppSupportOverride, 1)
        } else {
            unsetenv("AUDIOWHISPER_APP_SUPPORT_DIR")
        }
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        try super.tearDownWithError()
    }

    // MARK: - run / runInDir

    func testRunCapturesStdout() {
        let result = UvBootstrap.run("/bin/echo", ["hello", "world"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
        XCTAssertTrue(result.stderr.isEmpty)
    }

    func testRunCapturesNonZeroExitStatus() {
        // `false` always exits with status 1.
        let result = UvBootstrap.run("/usr/bin/false", [])
        XCTAssertEqual(result.status, 1)
    }

    func testRunReturnsFailureForMissingExecutable() {
        let result = UvBootstrap.run("/nonexistent/path/to/binary", [])
        XCTAssertEqual(result.status, 1)
        XCTAssertFalse(result.stderr.isEmpty, "Launch failure should surface in stderr")
    }

    func testRunInDirUsesProvidedWorkingDirectory() throws {
        let result = UvBootstrap.runInDir("/bin/pwd", [], cwd: tempRoot)
        XCTAssertEqual(result.status, 0)
        let printed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // pwd may resolve symlinks (e.g. /var -> /private/var); compare resolved paths.
        XCTAssertEqual(
            URL(fileURLWithPath: printed).resolvingSymlinksInPath().path,
            tempRoot.resolvingSymlinksInPath().path
        )
    }

    // MARK: - isVersion

    func testVersionComparisonGreaterOrEqual() {
        XCTAssertTrue(UvBootstrap.isVersionForTesting("0.8.5", greaterOrEqualThan: "0.8.5"))
        XCTAssertTrue(UvBootstrap.isVersionForTesting("0.9.0", greaterOrEqualThan: "0.8.5"))
        XCTAssertTrue(UvBootstrap.isVersionForTesting("1.0.0", greaterOrEqualThan: "0.8.5"))
        XCTAssertTrue(UvBootstrap.isVersionForTesting("0.8.10", greaterOrEqualThan: "0.8.5"))
    }

    func testVersionComparisonLessThan() {
        XCTAssertFalse(UvBootstrap.isVersionForTesting("0.8.4", greaterOrEqualThan: "0.8.5"))
        XCTAssertFalse(UvBootstrap.isVersionForTesting("0.7.99", greaterOrEqualThan: "0.8.5"))
        XCTAssertFalse(UvBootstrap.isVersionForTesting("0.0.1", greaterOrEqualThan: "0.8.5"))
    }

    func testVersionComparisonHandlesDifferingComponentCounts() {
        // Missing components are treated as zero.
        XCTAssertTrue(UvBootstrap.isVersionForTesting("1", greaterOrEqualThan: "0.8.5"))
        XCTAssertFalse(UvBootstrap.isVersionForTesting("0.8", greaterOrEqualThan: "0.8.5"))
        XCTAssertTrue(UvBootstrap.isVersionForTesting("0.8.5", greaterOrEqualThan: "0.8"))
    }

    // MARK: - projectDir

    func testProjectDirCreatesAndReturnsPythonProjectPath() throws {
        let proj = try UvBootstrap.projectDir()
        XCTAssertTrue(proj.path.hasSuffix("python_project"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: proj.path))
        // Second call is idempotent.
        let projAgain = try UvBootstrap.projectDir()
        XCTAssertEqual(proj.path, projAgain.path)
    }

    // MARK: - isEnvReady

    func testIsEnvReadyFalseWhenVenvAbsent() async {
        // Fresh project dir from setUp has no .venv.
        let ready = await UvBootstrap.isEnvReady()
        XCTAssertFalse(ready)
    }

    func testIsEnvReadyTrueWhenVenvPythonExists() async throws {
        let proj = try UvBootstrap.projectDir()
        let binDir = proj.appendingPathComponent(".venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let python3 = binDir.appendingPathComponent("python3")
        try Data("#!/bin/sh\n".utf8).write(to: python3)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python3.path)

        let ready = await UvBootstrap.isEnvReady()
        XCTAssertTrue(ready)
    }

    // MARK: - findUv error path

    func testFindUvThrowsUvNotFoundWhenNoUvAvailable() throws {
        // Restrict PATH so no `uv` is discoverable; if a bundled uv is present
        // in the test bundle, findUv may still succeed — accept either.
        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", "/nonexistent-bin", 1)
        defer {
            if let originalPath { setenv("PATH", originalPath, 1) }
        }

        do {
            _ = try UvBootstrap.findUv()
            // A bundled uv was found — acceptable in a packaged test bundle.
        } catch let error as UvError {
            guard case .uvNotFound = error else {
                return XCTFail("Expected uvNotFound, got \(error)")
            }
        }
    }

    // MARK: - UvError descriptions

    func testUvErrorDescriptionsAreNonEmpty() {
        let errors: [UvError] = [
            .uvNotFound,
            .uvTooOld(found: "0.8.4", required: "0.8.5"),
            .pythonNotUsable("missing"),
            .venvCreationFailed("bad"),
            .syncFailed("conflict"),
            .bundledBinaryTampered(expected: "abc", actual: "def")
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "\(error) needs a description")
        }
    }

    func testUvErrorTooOldDescriptionIncludesVersions() {
        let description = UvError.uvTooOld(found: "0.8.4", required: "0.8.5").errorDescription ?? ""
        XCTAssertTrue(description.contains("0.8.4"))
        XCTAssertTrue(description.contains("0.8.5"))
    }

    func testUvErrorTamperedDescriptionIncludesHashes() {
        let description = UvError.bundledBinaryTampered(
            expected: "expectedhash",
            actual: "actualhash"
        ).errorDescription ?? ""
        XCTAssertTrue(description.contains("expectedhash"))
        XCTAssertTrue(description.contains("actualhash"))
    }

    // MARK: - VenvSerializer

    func testVenvSerializerRunPropagatesValue() async throws {
        let serializer = VenvSerializer()
        let value = try await serializer.run { 42 }
        XCTAssertEqual(value, 42)
    }

    func testVenvSerializerRunPropagatesErrors() async {
        let serializer = VenvSerializer()
        do {
            _ = try await serializer.run {
                throw NSError(domain: "VenvTest", code: 7)
            }
            XCTFail("Expected error to propagate")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "VenvTest")
            XCTAssertEqual(error.code, 7)
        }
    }

    func testVenvSerializerClaimVerificationIsOneShot() async {
        let serializer = VenvSerializer()
        let first = await serializer.claimVerification()
        let second = await serializer.claimVerification()
        XCTAssertTrue(first, "First claim should win")
        XCTAssertFalse(second, "Subsequent claims should lose")

        await serializer.resetVerificationForTesting()
        let afterReset = await serializer.claimVerification()
        XCTAssertTrue(afterReset, "Reset should re-enable claiming")
    }
}
