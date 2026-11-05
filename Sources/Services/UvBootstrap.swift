import Foundation
import CryptoKit

internal enum UvError: Error, LocalizedError {
    case uvNotFound
    case uvTooOld(found: String, required: String)
    case pythonNotUsable(String)
    case venvCreationFailed(String)
    case syncFailed(String)
    case bundledBinaryTampered(expected: String, actual: String)
    case uvUnverified

    var errorDescription: String? {
        switch self {
        case .uvNotFound:
            return "uv not found. Install with: brew install uv — or bundle an arm64 uv at Sources/Resources/bin/uv."
        case let .uvTooOld(found, required):
            return "uv version \(found) is too old; require \(required)+"
        case .pythonNotUsable(let msg):
            return "Python not usable: \(msg)"
        case .venvCreationFailed(let msg):
            return "Failed to create venv: \(msg)"
        case .syncFailed(let msg):
            return "Failed to sync Python deps: \(msg)"
        case .uvUnverified:
            return "The uv found on this Mac doesn't match the copy AudioWhisper ships with, "
                + "so it wasn't used. Reinstall AudioWhisper."
        case let .bundledBinaryTampered(expected, actual):
            return "Bundled uv binary failed integrity check.\n  expected sha256: \(expected)\n  actual sha256:   \(actual)\nReinstall AudioWhisper from a trusted source."
        }
    }
}

/// Serializes venv-mutating operations so two callers (e.g. ParakeetService and
/// MLXCorrectionService racing at app launch) can't tread on each other.
internal actor VenvSerializer {
    static let shared = VenvSerializer()

    /// Tail of the operation chain. Each new `run` call chains a task behind
    /// the current tail and becomes the new tail — guaranteeing strict
    /// one-after-the-other execution even though `op` is async (a plain actor
    /// would otherwise admit a second caller at the first `await` inside `op`).
    private var chainTail: Task<Void, Never>?
    private var prepared: (key: String, python: URL)?

    func preparedPython(for key: String) -> URL? {
        guard let prepared, prepared.key == key,
              FileManager.default.isExecutableFile(atPath: prepared.python.path) else { return nil }
        return prepared.python
    }

    func rememberPreparation(key: String, python: URL) { prepared = (key, python) }
    func invalidatePreparation() { prepared = nil }

    /// Serialize an async, throwing operation. Concurrent callers execute
    /// strictly one-after-the-other: each call's work is wrapped in a `Task`
    /// that first awaits the previous link's completion, so no two `op` bodies
    /// ever overlap regardless of how many `await` points `op` contains.
    func run<T>(_ op: @escaping () async throws -> T) async throws -> T {
        let predecessor = chainTail
        // This link captures the operation's outcome. It only starts doing real
        // work after the predecessor link has fully completed.
        let link = Task<Result<T, Error>, Never> {
            await predecessor?.value
            do {
                return .success(try await op())
            } catch {
                return .failure(error)
            }
        }
        // The tail tracks only completion (not the value), erased to Void.
        let tail = Task<Void, Never> { _ = await link.value }
        chainTail = tail

        let result = await link.value
        // Drop the tail once this is the last completed link so an idle
        // serializer doesn't pin a finished task.
        if chainTail == tail { chainTail = nil }
        return try result.get()
    }

}

internal struct UvBootstrap {
    // Includes the entry-point, uninstall and archive security fixes.
    static let minUvVersion = "0.11.15"
    static let defaultPythonVersion = "3.11"

    // Where we keep the app-managed project (contains pyproject + .venv)
    static func projectDir() throws -> URL {
        let fm = FileManager.default
        let appSupportBase = try applicationSupportBaseDirectory()
        let appSupport = appSupportBase.appendingPathComponent(RebuildStorage.directoryName, isDirectory: true)
        if !fm.fileExists(atPath: appSupport.path) {
            try fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        let proj = appSupport.appendingPathComponent("python_project", isDirectory: true)
        if !fm.fileExists(atPath: proj.path) {
            try fm.createDirectory(at: proj, withIntermediateDirectories: true)
        }
        return proj
    }

    /// The uv this app runs. Only the copy whose SHA-256 matches the one
    /// recorded at build time is trusted: the bundled binary first, then a copy
    /// on PATH or in Application Support only if it is byte-identical. Anything
    /// else is skipped, because a user-writable `uv` would otherwise install and
    /// run arbitrary Python on the app's behalf.
    static func findUv() throws -> URL {
        #if DEBUG
        // Test seam: lets unit tests drive ensureVenv with a stub. Compiled out
        // of release builds, so it cannot redirect a shipped app.
        if let stub = ProcessInfo.processInfo.environment[testUvEnvironmentKey], !stub.isEmpty {
            let url = URL(fileURLWithPath: stub)
            let version = try uvVersion(at: url)
            guard isVersion(version, greaterOrEqualThan: minUvVersion) else {
                throw UvError.uvTooOld(found: version, required: minUvVersion)
            }
            return url
        }
        #endif
        return try selectUv(bundled: bundledUvCandidates(), fallbacks: fallbackUvCandidates(),
                            expectedSha256: VersionInfo.bundledUvSha256)
    }

    #if DEBUG
    static let testUvEnvironmentKey = "AUDIOWHISPER_TEST_UV"
    #endif

    /// Picks the first trusted uv. A bundled copy that fails its checksum is an
    /// error (the install is damaged); a fallback that fails is skipped.
    static func selectUv(bundled: [URL], fallbacks: [URL], expectedSha256: String) throws -> URL {
        let fileManager = FileManager.default
        var foundButOld: String?
        var skippedUnverified = false
        for url in bundled where fileManager.isExecutableFile(atPath: url.path) {
            try verifyUv(at: url, expected: expectedSha256)
            if let version = try? uvVersion(at: url) {
                if isVersion(version, greaterOrEqualThan: minUvVersion) { return url }
                foundButOld = foundButOld ?? version
            }
        }
        for url in fallbacks where fileManager.isExecutableFile(atPath: url.path) {
            guard (try? verifyUv(at: url, expected: expectedSha256)) != nil else {
                skippedUnverified = true
                continue
            }
            if let version = try? uvVersion(at: url) {
                if isVersion(version, greaterOrEqualThan: minUvVersion) { return url }
                foundButOld = foundButOld ?? version
            }
        }
        if let foundButOld { throw UvError.uvTooOld(found: foundButOld, required: minUvVersion) }
        throw skippedUnverified ? UvError.uvUnverified : UvError.uvNotFound
    }

    /// Release build (build.sh): Contents/Resources/bin/uv.
    /// Xcode/SPM build: AudioWhisper_AudioWhisper.bundle/Contents/Resources/Resources/bin/uv.
    private static func bundledUvCandidates() -> [URL] {
        [Bundle.main.resourceURL, ResourceLocator.moduleBundle?.resourceURL]
            .compactMap { $0 }
            .flatMap { [$0.appendingPathComponent("bin/uv"), $0.appendingPathComponent("Resources/bin/uv")] }
    }

    private static func fallbackUvCandidates() -> [URL] {
        var urls: [URL] = []
        if let pathUv = which("uv") { urls.append(URL(fileURLWithPath: pathUv)) }
        if let tools = try? applicationSupportBaseDirectory()
            .appendingPathComponent("\(RebuildStorage.directoryName)/bin/uv") {
            urls.append(tools)
        }
        return urls
    }

    // Ensure project exists and dependencies are synced with uv. Returns path to project .venv python.
    // If userPython is nil, we let uv provision or use its managed interpreter (via --python 3.x)
    //
    // Serialized through VenvSerializer so concurrent callers (Parakeet + MLX warmup
    // at app launch, etc.) don't race each other while creating the venv or running
    // `uv sync` on the same project directory.
    static func ensureVenv(
        userPython: String? = nil,
        forceRefresh: Bool = false,
        log: ((String) -> Void)? = nil
    ) async throws -> URL {
        try await VenvSerializer.shared.run {
            let proj = try projectDir()
            let key = try preparationKey(project: proj, python: userPython)
            if !forceRefresh, let cached = await VenvSerializer.shared.preparedPython(for: key) { return cached }
            await VenvSerializer.shared.invalidatePreparation()
            let uv = try findUv()

            let fm = FileManager.default
            // Copy pyproject.toml and uv.lock from bundle to project dir (if present / newer)
            try copyProjectFilesIfNeeded(to: proj)

            // Ensure .venv exists using specified Python (or default)
            let venvDir = proj.appendingPathComponent(".venv", isDirectory: true)
            let pythonSpecifier = userPython.flatMap { $0.isEmpty ? nil : $0 } ?? defaultPythonVersion
            let specFile = proj.appendingPathComponent(".audiowhisper-python-specifier")
            let previousSpecifier = try? String(contentsOf: specFile, encoding: .utf8)
            let changedPython = previousSpecifier.map { $0 != pythonSpecifier } ?? (userPython != nil)
            if !fm.fileExists(atPath: venvDir.path) || changedPython {
                log?("Creating project .venv with Python \(pythonSpecifier)…")
                let venvResult = await runInDir(
                    uv.path, ["venv", "--clear", "--python", pythonSpecifier], cwd: proj, timeout: .seconds(600))
                if venvResult.status != 0 {
                    throw UvError.venvCreationFailed(
                        venvResult.stderr.isEmpty ? venvResult.stdout : venvResult.stderr
                    )
                }
            }

            // Install only the shipped lock. A failed sync stays actionable;
            // retrying against an unlocked dependency tree changes the product.
            log?("Syncing project dependencies via uv sync…")
            // Generous: the first sync downloads several hundred MB of MLX wheels.
            let syncResult = await runInDir(uv.path, ["sync", "--frozen"], cwd: proj, timeout: .seconds(1800))

            if syncResult.status != 0 {
                throw UvError.syncFailed(
                    syncResult.stderr.isEmpty ? syncResult.stdout : syncResult.stderr
                )
            }

            // Return the project venv python
            let candidates = [
                proj.appendingPathComponent(".venv/bin/python3").path,
                proj.appendingPathComponent(".venv/bin/python").path
            ]
            for candidate in candidates where fm.isExecutableFile(atPath: candidate) {
                let python = URL(fileURLWithPath: candidate)
                guard await environmentImportsWork(python: python, project: proj) else {
                    throw UvError.pythonNotUsable("runtime dependencies could not be imported; reinstall dependencies in Setup")
                }
                try pythonSpecifier.write(to: specFile, atomically: true, encoding: .utf8)
                let preparedKey = try preparationKey(project: proj, python: userPython)
                await VenvSerializer.shared.rememberPreparation(key: preparedKey, python: python)
                return python
            }
            throw UvError.pythonNotUsable("project venv python not found")
        }
    }

    /// Must run before even a bundled `uv --version` probe.
    static func verifyUv(at url: URL, expected: String) throws {
        guard expected.count == 64, expected.allSatisfy(\.isHexDigit) else {
            throw UvError.pythonNotUsable("bundled uv checksum is missing; rebuild or reinstall AudioWhisper")
        }
        let actual = try fileHash(url)
        guard actual.lowercased() == expected.lowercased() else {
            throw UvError.bundledBinaryTampered(expected: expected.lowercased(), actual: actual)
        }
    }

    static func verifiedUvVersion(at url: URL, expected: String) throws -> String {
        try verifyUv(at: url, expected: expected)
        return try uvVersion(at: url)
    }

    // Copy pyproject.toml and uv.lock from bundle to per-user project dir
    /// Check if the Python environment is ready (venv exists with python executable)
    static func isEnvReady() async -> Bool {
        do {
            return try await VenvSerializer.shared.run {
                let proj = try projectDir()
                let key = try preparationKey(project: proj, python: nil)
                if await VenvSerializer.shared.preparedPython(for: key) != nil { return true }
                for name in ["pyproject.toml", "uv.lock"] {
                    let bundledHash = try fileHash(bundledProjectFile(name))
                    guard try bundledHash == fileHash(proj.appendingPathComponent(name)) else { return false }
                }
                let python = proj.appendingPathComponent(".venv/bin/python3")
                return await environmentImportsWork(python: python, project: proj)
            }
        } catch { return false }
    }

    /// Automation validates the installed lock and imports without creating a
    /// project, syncing dependencies, finding uv, or downloading Python.
    static func installedPython() async throws -> URL {
        let project = try applicationSupportBaseDirectory(create: false).appendingPathComponent(RebuildStorage.directoryName)
            .appendingPathComponent("python_project")
        guard FileManager.default.fileExists(atPath: project.path) else { throw PublicAutomationError.assets }
        for name in ["pyproject.toml", "uv.lock"] {
            guard try fileHash(bundledProjectFile(name)) == fileHash(project.appendingPathComponent(name)) else {
                throw PublicAutomationError.assets
            }
        }
        let python = project.appendingPathComponent(".venv/bin/python3")
        let ready = await environmentImportsWork(python: python, project: project)
        guard ready else { throw PublicAutomationError.assets }
        return python
    }

    /// Copies `pyproject.toml` AND `uv.lock` from the bundle into the per-user
    /// project directory.
    ///
    /// The lock used to be deliberately skipped ("to avoid mismatches"), which
    /// combined with a plain `uv sync` meant the app resolved its whole Python
    /// dependency tree live from PyPI on first launch. In an unsandboxed app
    /// holding Microphone and Accessibility permissions, that is an unpinned
    /// code-execution path. `ensureVenv` now runs `uv sync --frozen` against the
    /// copied lock, and handles the mismatch case explicitly instead of avoiding
    /// it by never shipping the lock (E1).
    ///
    private static func copyProjectFilesIfNeeded(to proj: URL) throws {
        for name in ["pyproject.toml", "uv.lock"] {
            try copyIfDifferent(src: bundledProjectFile(name), dst: proj.appendingPathComponent(name))
        }
    }

    // MARK: - Utilities

    private static func which(_ cmd: String) -> String? {
        let result = run("/usr/bin/which", [cmd])
        guard result.status == 0 else { return nil }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Debug builds let tests redirect Application Support via an env var;
    /// release builds always use the real per-user directory.
    private static func applicationSupportBaseDirectory(create: Bool = true) throws -> URL {
        let fm = FileManager.default
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["AUDIOWHISPER_APP_SUPPORT_DIR"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if create, !fm.fileExists(atPath: url.path) {
                try fm.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        }
        #endif
        return try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: create)
    }

    private static func uvVersion(at url: URL) throws -> String {
        let result = run(url.path, ["--version"])
        guard result.status == 0 else {
            throw UvError.syncFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        let versionOutput = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // Common formats:
        //  - "uv 0.8.5 (ce3728681 2025-08-05)"
        //  - "uv 0.8.5"
        //  - "0.8.5"
        let semverPattern = #"\d+\.\d+\.\d+([\-\+][A-Za-z0-9\.\-]+)?"#
        if let range = versionOutput.range(of: semverPattern, options: .regularExpression) {
            return String(versionOutput[range])
        }
        let components = versionOutput.split(separator: " ")
        if components.count >= 2 && components[0].lowercased() == "uv" {
            return String(components[1])
        }
        return versionOutput
    }

    /// Test seam over the file-private version comparison.
    static func isVersionForTesting(_ version: String, greaterOrEqualThan minimum: String) -> Bool {
        isVersion(version, greaterOrEqualThan: minimum)
    }

    /// Test seam over the file-private content-aware copy.
    static func copyIfDifferentForTesting(src: URL, dst: URL) throws {
        try copyIfDifferent(src: src, dst: dst)
    }

    private static func isVersion(_ version: String, greaterOrEqualThan minimum: String) -> Bool {
        func parse(_ text: String) -> [Int] { text.split(separator: ".").compactMap { Int($0) } }
        let versionParts = parse(version)
        let minimumParts = parse(minimum)
        for index in 0..<max(versionParts.count, minimumParts.count) {
            let versionPart = index < versionParts.count ? versionParts[index] : 0
            let minimumPart = index < minimumParts.count ? minimumParts[index] : 0
            if versionPart != minimumPart { return versionPart > minimumPart }
        }
        return true
    }

    /// Copies `src` to `dst` only when their contents differ.
    ///
    /// Compares by SHA-256 of the file contents rather than size + mtime: a
    /// same-size pyproject.toml with different bytes (and an equal/older mtime)
    /// previously slipped through, leaving stale Python deps after an app
    /// update. These files are tiny, so a content hash is cheap and exact.
    private static func copyIfDifferent(src: URL, dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) {
            if let srcHash = try? fileHash(src),
               let dstHash = try? fileHash(dst),
               srcHash == dstHash {
                return
            }
            try fm.removeItem(at: dst)
        }
        try fm.copyItem(at: src, to: dst)
    }

    /// SHA-256 of a file's full contents, lower-case hex.
    static func fileHash(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
