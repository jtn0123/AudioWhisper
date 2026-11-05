import CryptoKit
import Foundation
import XCTest
@testable import AudioWhisper

final class UvBootstrapTests: XCTestCase {
    private var originalHome: String?
    private var originalPath: String?
    private var originalAppSupportOverride: String?
    private var tempHome: URL!
    private var tempAppSupport: URL!
    private var tempBin: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalHome = ProcessInfo.processInfo.environment["HOME"]
        originalPath = ProcessInfo.processInfo.environment["PATH"]
        originalAppSupportOverride = ProcessInfo.processInfo.environment["AUDIOWHISPER_APP_SUPPORT_DIR"]

        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("UvBootstrapTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        tempHome = tempRoot
        tempAppSupport = tempRoot.appendingPathComponent("AppSupport", isDirectory: true)
        try FileManager.default.createDirectory(at: tempAppSupport, withIntermediateDirectories: true)
        tempBin = tempRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: tempBin, withIntermediateDirectories: true)

        setenv("HOME", tempHome.path, 1)
        setenv("AUDIOWHISPER_APP_SUPPORT_DIR", tempAppSupport.path, 1)
        // Keep /usr/bin last so tools like /usr/bin/env remain reachable while excluding any real uv in default paths.
        setenv("PATH", "\(tempBin.path):/usr/bin:/bin", 1)
    }

    override func tearDownWithError() throws {
        if let originalHome {
            setenv("HOME", originalHome, 1)
        }
        if let originalPath {
            setenv("PATH", originalPath, 1)
        }
        if let originalAppSupportOverride {
            setenv("AUDIOWHISPER_APP_SUPPORT_DIR", originalAppSupportOverride, 1)
        } else {
            unsetenv("AUDIOWHISPER_APP_SUPPORT_DIR")
        }
        unsetenv(UvBootstrap.testUvEnvironmentKey)
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
        try super.tearDownWithError()
    }

    func testFindUvThrowsWhenUvTooOld() throws {
        try writeUvStub(version: "0.8.4")
        XCTAssertThrowsError(try UvBootstrap.findUv()) { error in
            guard case let .uvTooOld(found, required)? = error as? UvError else {
                return XCTFail("Expected uvTooOld, got \(error)")
            }
            XCTAssertEqual(found, "0.8.4")
            XCTAssertEqual(required, UvBootstrap.minUvVersion)
        }
    }

    // MARK: - Trusted uv selection

    func testUnverifiedFallbacksAreNeverRun() throws {
        let marker = tempHome.appendingPathComponent("executed")
        let rogue = tempBin.appendingPathComponent("uv")
        try writeExecutable("#!/bin/bash\ntouch '\(marker.path)'\necho 'uv 0.12.23'\n", to: rogue)
        let expected = String(repeating: "a", count: 64)
        XCTAssertThrowsError(try UvBootstrap.selectUv(bundled: [], fallbacks: [rogue], expectedSha256: expected)) {
            guard case .uvUnverified? = $0 as? UvError else { return XCTFail("Expected uvUnverified, got \($0)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "An unverified uv must not even be probed")
    }

    func testFallbackIdenticalToTheShippedBinaryIsAccepted() throws {
        let copy = tempBin.appendingPathComponent("uv")
        try writeExecutable("#!/bin/bash\necho 'uv 0.12.23'\n", to: copy)
        let found = try UvBootstrap.selectUv(bundled: [], fallbacks: [copy], expectedSha256: try sha256(copy))
        XCTAssertEqual(found, copy)
    }

    func testBundledCopyWinsOverAFallbackOnPath() throws {
        let bundled = tempHome.appendingPathComponent("bundled-uv")
        let onPath = tempBin.appendingPathComponent("uv")
        try writeExecutable("#!/bin/bash\necho 'uv 0.12.23'\n", to: bundled)
        try writeExecutable("#!/bin/bash\necho 'uv 0.12.23'\n", to: onPath)
        let found = try UvBootstrap.selectUv(bundled: [bundled], fallbacks: [onPath], expectedSha256: try sha256(bundled))
        XCTAssertEqual(found, bundled)
    }

    func testTamperedBundledCopyFailsInsteadOfFallingBack() throws {
        let bundled = tempHome.appendingPathComponent("bundled-uv")
        let onPath = tempBin.appendingPathComponent("uv")
        try writeExecutable("#!/bin/bash\necho 'uv 0.12.23'\n", to: onPath)
        try writeExecutable("#!/bin/bash\necho 'uv 0.12.23' # modified\n", to: bundled)
        XCTAssertThrowsError(try UvBootstrap.selectUv(bundled: [bundled], fallbacks: [onPath],
                                                      expectedSha256: try sha256(onPath))) {
            guard case .bundledBinaryTampered? = $0 as? UvError else {
                return XCTFail("Expected bundledBinaryTampered, got \($0)")
            }
        }
    }

    func testNoCandidatesReportsNotFound() {
        let missing = tempBin.appendingPathComponent("absent")
        XCTAssertThrowsError(try UvBootstrap.selectUv(bundled: [missing], fallbacks: [missing],
                                                      expectedSha256: String(repeating: "a", count: 64))) {
            guard case .uvNotFound? = $0 as? UvError else { return XCTFail("Expected uvNotFound, got \($0)") }
        }
    }

    func testEnsureVenvCreatesAndSyncsWithDefaultPython() async throws {
        let logURL = tempHome.appendingPathComponent("uv_invocations.log")
        let uvURL = try writeUvStub(version: "0.12.23", logFile: logURL)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: uvURL.path))

        let project = try UvBootstrap.projectDir()
        // Pre-seed a minimal venv layout to avoid relying on the stub creating files.
        let pythonBin = project.appendingPathComponent(".venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pythonBin, withIntermediateDirectories: true)
        let pythonFile = pythonBin.appendingPathComponent("python3")
        try "#!/bin/bash\necho python\n".write(to: pythonFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pythonFile.path)

        var logMessages: [String] = []
        let pythonURL: URL
        do {
            pythonURL = try await UvBootstrap.ensureVenv(userPython: nil) { logMessages.append($0) }
        } catch {
            let binPath = project.appendingPathComponent(".venv/bin")
            let binContents = try? FileManager.default.contentsOfDirectory(atPath: binPath.path)
            let logContents = (try? String(contentsOf: logURL)) ?? "<empty>"
            let exists = FileManager.default.fileExists(atPath: binPath.path)
            let python3Exists = FileManager.default.isExecutableFile(atPath: binPath.appendingPathComponent("python3").path)
            XCTFail("ensureVenv threw \(error); project: \(project.path); binExists: \(exists); python3Exists: \(python3Exists); .venv/bin contents: \(binContents ?? []); log: \(logContents)")
            return
        }

        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: pythonURL.path))
        XCTAssertTrue(pythonURL.path.hasSuffix(".venv/bin/python3"))
        XCTAssertEqual(logMessages.first, "Syncing project dependencies via uv sync…")
        XCTAssertEqual(logMessages.last, "Syncing project dependencies via uv sync…")

        let invocations = try String(contentsOf: logURL).split(separator: "\n")
        XCTAssertTrue(invocations.contains(where: { $0.contains("--version") }))
        XCTAssertTrue(
            invocations.contains(where: { $0.contains("venv --clear --python \(UvBootstrap.defaultPythonVersion)") }) ||
            FileManager.default.fileExists(atPath: project.appendingPathComponent(".venv").path)
        )
        XCTAssertTrue(invocations.contains(where: { $0.contains("sync") }))
    }

    /// The stub uv above accepts `sync` with or without a project, so the test
    /// above passes even when no pyproject.toml was ever copied. That is exactly
    /// what happened under SwiftPM's native build layout, where the resource
    /// bundle sits beside the .xctest rather than inside it: the real `uv sync`
    /// found nothing to sync, and the nightly end-to-end run failed every night.
    func testEnsureVenvCopiesTheBundledProjectAndSyncsFrozen() async throws {
        let logURL = tempHome.appendingPathComponent("uv_invocations.log")
        try writeUvStub(version: "0.12.23", logFile: logURL)
        let project = try UvBootstrap.projectDir()
        let pythonBin = project.appendingPathComponent(".venv/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: pythonBin, withIntermediateDirectories: true)
        try writeExecutable("#!/bin/bash\necho python\n", to: pythonBin.appendingPathComponent("python3"))

        _ = try await UvBootstrap.ensureVenv(userPython: nil)

        for name in ["pyproject.toml", "uv.lock"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: project.appendingPathComponent(name).path),
                "\(name) was not copied from the resource bundle into \(project.path)"
            )
        }
        let invocations = try String(contentsOf: logURL, encoding: .utf8).split(separator: "\n")
        XCTAssertTrue(
            invocations.contains(where: { $0.hasSuffix(":: sync --frozen") }),
            "with a bundled lock, sync must be --frozen; got \(invocations)"
        )
    }

    func testFailedFrozenSyncDoesNotRunUnlockedResolution() async throws {
        let log = tempHome.appendingPathComponent("sync.log")
        try writeExecutable("""
        #!/bin/bash
        echo "$*" >> '\(log.path)'
        if [[ "$1" == "--version" ]]; then echo 'uv 0.12.23'; exit 0; fi
        if [[ "$1" == "sync" && "$2" == "--frozen" ]]; then echo 'pinned failure' >&2; exit 1; fi
        if [[ "$1" == "venv" ]]; then mkdir -p .venv; exit 0; fi
        exit 0
        """, to: tempBin.appendingPathComponent("uv"))
        setenv(UvBootstrap.testUvEnvironmentKey, tempBin.appendingPathComponent("uv").path, 1)
        do {
            _ = try await UvBootstrap.ensureVenv()
            XCTFail("expected pinned install failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("pinned failure"))
        }
        let invocations = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(invocations.filter { $0.hasPrefix("sync") }, ["sync --frozen"])
    }

    func testUnverifiedBinaryCannotExecuteAndFailedChecksRemainRetryable() throws {
        let marker = tempHome.appendingPathComponent("executed")
        let binary = tempBin.appendingPathComponent("unverified")
        try writeExecutable("#!/bin/bash\ntouch '\(marker.path)'\necho 'uv 0.12.23'\n", to: binary)
        for _ in 0..<2 {
            XCTAssertThrowsError(try UvBootstrap.verifiedUvVersion(at: binary, expected: String(repeating: "0", count: 64)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        }
        XCTAssertThrowsError(try UvBootstrap.verifiedUvVersion(at: binary, expected: ""))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
    }

    // MARK: - Helpers

    func testWarmAndConcurrentPreparationsSyncOnceAndRecoverDeletedInterpreter() async throws {
        let log = tempHome.appendingPathComponent("warm.log")
        try writeUvStub(version: "0.12.23", logFile: log)
        let initial = try await UvBootstrap.ensureVenv()
        try await withThrowingTaskGroup(of: URL.self) { group in
            for _ in 0..<8 { group.addTask { try await UvBootstrap.ensureVenv() } }
            for try await python in group { XCTAssertEqual(python, initial) }
        }
        var invocations = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(invocations.filter { $0.contains(":: sync") }.count, 1)
        try FileManager.default.removeItem(at: initial)
        _ = try await UvBootstrap.ensureVenv()
        invocations = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(invocations.filter { $0.contains(":: sync") }.count, 2)
    }

    func testChangedLockAndExplicitRefreshInvalidateWarmPreparation() async throws {
        let log = tempHome.appendingPathComponent("invalidate.log")
        try writeUvStub(version: "0.12.23", logFile: log)
        _ = try await UvBootstrap.ensureVenv()
        let project = try UvBootstrap.projectDir()
        try "changed lock".write(to: project.appendingPathComponent("uv.lock"), atomically: true, encoding: .utf8)
        _ = try await UvBootstrap.ensureVenv()
        _ = try await UvBootstrap.ensureVenv(forceRefresh: true)
        let invocations = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(invocations.filter { $0.contains(":: sync") }.count, 3)
    }

    @discardableResult
    private func writeUvStub(version: String, logFile: URL? = nil) throws -> URL {
        let uvURL = tempBin.appendingPathComponent("uv")
        var lines: [String] = ["#!/bin/bash"]
        lines.append("dir=\"$(pwd)\"")
        if let logFile {
            lines.append("echo \"$dir :: $*\" >> \"\(logFile.path)\"")
        }
        lines.append("if [[ \"$1\" == \"--version\" ]]; then")
        lines.append("  echo 'uv \(version)'")
        lines.append("  exit 0")
        lines.append("fi")
        // Always ensure a minimal venv layout so tests remain deterministic
        lines.append("mkdir -p \"$dir/.venv/bin\"")
        lines.append("cat > \"$dir/.venv/bin/python3\" <<'PY'\n#!/bin/bash\necho python\nPY")
        lines.append("chmod +x \"$dir/.venv/bin/python3\"")
        lines.append("ln -sf python3 \"$dir/.venv/bin/python\"")
        lines.append("if [[ \"$1\" == \"venv\" ]]; then")
        lines.append("  exit 0")
        lines.append("fi")
        lines.append("if [[ \"$1\" == \"sync\" ]]; then")
        lines.append("  exit 0")
        lines.append("fi")
        lines.append("echo 'unexpected args' >&2")
        lines.append("exit 1")

        try writeExecutable(lines.joined(separator: "\n") + "\n", to: uvURL)
        setenv(UvBootstrap.testUvEnvironmentKey, uvURL.path, 1)
        return uvURL
    }

    private func sha256(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        let data = Data(contents.utf8)
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
