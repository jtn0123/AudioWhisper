import XCTest
@testable import AudioWhisper

/// Tests for `MLXModelManager+Cache.swift`: repo validation, cache detection,
/// deletion, and the Parakeet download driven end to end against a stub `uv`
/// and a fake venv python.
///
/// Anything that touches the Hugging Face cache uses a UUID-scoped repo name at
/// the real cache path (`integrityFileURL` resolves from the OS home directory
/// and ignores `HOME`), and removes it afterwards, so a developer's genuinely
/// cached models are never read as fixtures or deleted.
@MainActor
final class MLXModelManagerCacheTests: XCTestCase {

    private var manager: MLXModelManager { MLXModelManager.shared }
    private var savedPath: String?
    private var savedAppSupport: String?
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        savedPath = ProcessInfo.processInfo.environment["PATH"]
        savedAppSupport = ProcessInfo.processInfo.environment["AUDIOWHISPER_APP_SUPPORT_DIR"]
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MLXModelManagerCacheTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let savedPath { setenv("PATH", savedPath, 1) }
        if let savedAppSupport {
            setenv("AUDIOWHISPER_APP_SUPPORT_DIR", savedAppSupport, 1)
        } else {
            unsetenv("AUDIOWHISPER_APP_SUPPORT_DIR")
        }
        AppDefaults.defaults.removeObject(forKey: AppDefaults.Key.selectedParakeetModel.rawValue)
        try? FileManager.default.removeItem(at: tempRoot)
        try super.tearDownWithError()
    }

    // MARK: - isValidRepoIdentifier

    func testValidRepoIdentifiersAreAccepted() {
        for repo in ["mlx-community/parakeet-tdt-0.6b-v3", "org/name", "a_b/c.d-e", "A1/B2"] {
            XCTAssertTrue(MLXModelManager.isValidRepoIdentifier(repo), repo)
        }
    }

    /// deleteModel turns this string into a path under the cache, so anything
    /// that could escape that directory has to be refused here.
    func testRepoIdentifiersThatCouldEscapeTheCacheAreRejected() {
        let rejected = [
            "",
            "/etc/passwd",
            "org/../../secrets",
            "..",
            "org/name\u{0}",
            "org/na\nme",
            "no-slash",
            "too/many/slashes",
            "/name",
            "org/",
            "org/name with space",
            "org/naïve"
        ]
        for repo in rejected {
            XCTAssertFalse(MLXModelManager.isValidRepoIdentifier(repo), repo.debugDescription)
        }
    }

    // MARK: - applyDownloadProgressLine

    func testProgressLinesUpdateTheDisplayedProgress() {
        let repo = uniqueRepo()
        defer { manager.downloadProgress.removeValue(forKey: repo) }

        let event = manager.applyDownloadProgressLine(
            #"{"status": "downloading", "message": "Fetching weights"}"#, for: repo
        )
        XCTAssertEqual(event, .progress("Fetching weights"))
        XCTAssertEqual(manager.downloadProgress[repo], "Fetching weights")

        manager.applyDownloadProgressLine(#"{"status": "error", "message": "disk full"}"#, for: repo)
        XCTAssertEqual(manager.downloadProgress[repo], "Error: disk full")
    }

    func testUnstructuredAndCompleteLinesLeaveTheProgressAlone() {
        let repo = uniqueRepo()
        defer { manager.downloadProgress.removeValue(forKey: repo) }
        manager.downloadProgress[repo] = "Downloading…"

        XCTAssertEqual(
            manager.applyDownloadProgressLine("Fetching 4 files: 50%", for: repo),
            .unstructured("Fetching 4 files: 50%")
        )
        XCTAssertEqual(manager.applyDownloadProgressLine("", for: repo), .unstructured(""))
        XCTAssertEqual(manager.applyDownloadProgressLine(#"{"status": "complete"}"#, for: repo), .complete)
        XCTAssertEqual(manager.downloadProgress[repo], "Downloading…")
    }

    // MARK: - isModelCachedOnDisk

    func testASnapshotThatIsAFileIsNotACachedModel() throws {
        let repo = uniqueRepo()
        let revision = String(repeating: "c0ffee00", count: 5)
        let modelDir = try makeFakeHFCache(repo: repo, revision: revision, createSnapshotDir: false)
        let snapshots = modelDir.appendingPathComponent("snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try Data().write(to: snapshots.appendingPathComponent(revision))

        XCTAssertFalse(manager.isModelCachedOnDisk(repo: repo))
    }

    /// The integrity record is trust-on-first-use: once a revision is recorded,
    /// a cache whose `refs/main` has been changed underneath it no longer
    /// counts as present, which is what triggers a fresh download.
    func testACacheThatNoLongerMatchesItsIntegrityRecordIsNotCached() throws {
        let repo = uniqueRepo()
        let original = String(repeating: "aaaa1111", count: 5)
        let modelDir = try makeFakeHFCache(repo: repo, revision: original)
        manager.recordIntegrity(for: repo)
        XCTAssertTrue(manager.isModelCachedOnDisk(repo: repo))

        let swapped = String(repeating: "bbbb2222", count: 5)
        try FileManager.default.createDirectory(
            at: modelDir.appendingPathComponent("snapshots/\(swapped)"),
            withIntermediateDirectories: true
        )
        try swapped.write(to: modelDir.appendingPathComponent("refs/main"), atomically: true, encoding: .utf8)

        XCTAssertFalse(manager.isModelCachedOnDisk(repo: repo))
    }

    // MARK: - ensureParakeetModel

    func testEnsureParakeetModelDoesNotDownloadWhenTheModelIsOnDisk() async throws {
        let repo = uniqueRepo()
        _ = try makeFakeHFCache(repo: repo, revision: String(repeating: "12345678", count: 5))
        selectParakeetRepo(repo)

        await manager.ensureParakeetModel()

        XCTAssertNil(manager.isDownloading[repo], "a cached model must not start a download")
        XCTAssertNil(manager.downloadProgress[repo])
    }

    func testEnsureParakeetModelDownloadsWhenTheModelIsMissing() async throws {
        let repo = uniqueRepo()
        let argsFile = tempRoot.appendingPathComponent("python-args.txt")
        try installStubPython(body: """
            printf '%s\\n' "$@" > '\(argsFile.path)'
            echo '{"status": "complete", "message": "Model ready"}'
            exit 0
            """)
        selectParakeetRepo(repo)

        await manager.ensureParakeetModel()
        await waitForDownloadToFinish(repo)

        XCTAssertEqual(manager.isDownloading[repo], false)
        XCTAssertNil(manager.downloadProgress[repo], "a finished download clears its progress text")
        let args = try String(contentsOf: argsFile, encoding: .utf8).split(separator: "\n").map(String.init)
        XCTAssertTrue(args.contains(repo), "the repo is passed as an argument, got \(args)")
    }

    // MARK: - downloadParakeetModel

    func testAFailedParakeetDownloadIsReportedAsAnError() async throws {
        let repo = uniqueRepo()
        try installStubPython(body: """
            echo 'Traceback (most recent call last): ...' >&2
            echo '{"status": "error", "message": "Repository not found"}'
            exit 1
            """)
        selectParakeetRepo(repo)

        await manager.downloadParakeetModel()
        await waitForDownloadToFinish(repo)

        XCTAssertEqual(manager.isDownloading[repo], false)
        let progress = manager.downloadProgress[repo] ?? ""
        XCTAssertTrue(progress.hasPrefix("Error: "), "got \(progress.debugDescription)")
        manager.downloadProgress.removeValue(forKey: repo)
    }

    func testAParakeetDownloadWithNoUsablePythonEnvironmentReportsIt() async throws {
        let repo = uniqueRepo()
        try installStubUv(venvSucceeds: false)
        selectParakeetRepo(repo)

        await manager.downloadParakeetModel()

        XCTAssertEqual(manager.isDownloading[repo], false)
        XCTAssertEqual(manager.downloadProgress[repo], "Error: Could not prepare Python environment")
        manager.downloadProgress.removeValue(forKey: repo)
    }

    // MARK: - deleteModel

    func testDeleteModelRemovesTheCachedModel() async throws {
        let repo = uniqueRepo()
        let modelDir = try makeFakeHFCache(repo: repo, revision: String(repeating: "abcdef01", count: 5))
        manager.downloadedModels.insert(repo)
        manager.modelSizes[repo] = 1

        await manager.deleteModel(repo)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDir.path))
        XCTAssertFalse(manager.downloadedModels.contains(repo))
        XCTAssertNil(manager.modelSizes[repo])
    }

    func testDeleteModelOfAModelThatIsNotCachedIsHarmless() async {
        let repo = uniqueRepo()
        manager.downloadedModels.insert(repo)

        await manager.deleteModel(repo)

        // Removal failed, so the in-memory state is left for the next refresh.
        XCTAssertTrue(manager.downloadedModels.contains(repo))
        manager.downloadedModels.remove(repo)
    }

    func testDeleteModelRefusesAnInvalidIdentifier() async throws {
        // A directory the traversal would land on if it were not refused.
        let victim = tempRoot.appendingPathComponent("victim", isDirectory: true)
        try FileManager.default.createDirectory(at: victim, withIntermediateDirectories: true)
        let traversal = "../../../../../../../../..\(victim.path)"

        await manager.deleteModel(traversal)

        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))
    }

    // MARK: - Helpers

    private func uniqueRepo() -> String {
        "audiowhisper-test/cache-\(UUID().uuidString)"
    }

    private func selectParakeetRepo(_ repo: String) {
        AppDefaults.defaults.set(repo, forKey: AppDefaults.Key.selectedParakeetModel.rawValue)
        XCTAssertEqual(MLXModelManager.parakeetRepo, repo)
    }

    /// `<hub>/models--<escaped>/{refs/main, snapshots/<rev>/, blobs/}` at the
    /// real cache path, removed again at teardown.
    private func makeFakeHFCache(repo: String, revision: String, createSnapshotDir: Bool = true) throws -> URL {
        let refsMain = try XCTUnwrap(manager.integrityFileURL(for: repo))
        let modelDir = refsMain.deletingLastPathComponent().deletingLastPathComponent()
        addTeardownBlock { try? FileManager.default.removeItem(at: modelDir) }
        try FileManager.default.createDirectory(
            at: refsMain.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try revision.write(to: refsMain, atomically: true, encoding: .utf8)
        if createSnapshotDir {
            try FileManager.default.createDirectory(
                at: modelDir.appendingPathComponent("snapshots/\(revision)"),
                withIntermediateDirectories: true
            )
        }
        return modelDir
    }

    /// Puts a stub `uv` first on PATH and points UvBootstrap's project dir into
    /// the temp root. `uv` on PATH is preferred over a bundled one, so this is
    /// what `ensureVenv` runs.
    private func installStubUv(venvSucceeds: Bool) throws {
        let bin = tempRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try writeExecutable("""
            #!/bin/bash
            case "$1" in
              --version) echo 'uv 0.9.0'; exit 0 ;;
              venv) \(venvSucceeds ? "exit 0" : "echo 'no interpreter found' >&2; exit 1") ;;
              sync) exit 0 ;;
            esac
            echo "unexpected uv invocation: $*" >&2
            exit 1
            """, to: bin.appendingPathComponent("uv"))
        setenv("PATH", "\(bin.path):/usr/bin:/bin", 1)
        setenv("AUDIOWHISPER_APP_SUPPORT_DIR", tempRoot.appendingPathComponent("AppSupport").path, 1)
    }

    /// Installs the stub uv plus a venv whose `python3` is a bash script with
    /// `body`, standing in for the download script.
    private func installStubPython(body: String) throws {
        try installStubUv(venvSucceeds: true)
        let python = try UvBootstrap.projectDir().appendingPathComponent(".venv/bin/python3")
        try FileManager.default.createDirectory(
            at: python.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try writeExecutable("#!/bin/bash\n\(body)\n", to: python)
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// The download returns once the subprocess has been started or, in later
    /// versions, once it has exited; either way this waits for the exit.
    private func waitForDownloadToFinish(_ repo: String, timeout: Duration = .seconds(20)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while manager.isDownloading[repo] == true, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotEqual(manager.isDownloading[repo], true, "download of \(repo) never finished")
    }
}
