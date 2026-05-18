import XCTest
@testable import AudioWhisper

private final class MockMLDaemon: MLDaemonManaging {
    var lastRepo: String?
    var lastText: String?
    var lastPrompt: String?
    var nextCorrectResult: Result<String, Error> = .success("corrected")
    var pingResult: Bool = true
    
    func correct(repo: String, text: String, prompt: String?) async throws -> String {
        lastRepo = repo
        lastText = text
        lastPrompt = prompt
        return try nextCorrectResult.get()
    }
    
    func ping() async -> Bool {
        pingResult
    }
}

final class MLXCorrectionServiceTests: XCTestCase {
    func testCorrectUsesPromptLoaderAndReturnsResult() async throws {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .success("fixed text")
        
        var loaderCalled = false
        let service = MLXCorrectionService(
            daemon: daemon,
            promptLoader: {
                loaderCalled = true
                return "file prompt"
            }
        )
        
        let result = try await service.correct(
            text: "hello",
            modelRepo: "mlx-community/model",
            pythonPath: "/tmp/python"
        )
        
        XCTAssertEqual(result, "fixed text")
        XCTAssertTrue(loaderCalled, "Prompt loader should be used when systemPrompt is nil")
        XCTAssertEqual(daemon.lastRepo, "mlx-community/model")
        XCTAssertEqual(daemon.lastText, "hello")
        XCTAssertEqual(daemon.lastPrompt, "file prompt")
    }
    
    func testCorrectPrefersExplicitSystemPrompt() async throws {
        let daemon = MockMLDaemon()
        let service = MLXCorrectionService(
            daemon: daemon,
            promptLoader: { "fallback prompt" }
        )
        
        _ = try await service.correct(
            text: "hi",
            modelRepo: "repo",
            pythonPath: "/tmp/python",
            systemPrompt: "explicit prompt"
        )
        
        XCTAssertEqual(daemon.lastPrompt, "explicit prompt", "Explicit systemPrompt should override loader")
    }
    
    func testCorrectMapsDependencyMissingError() async {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .failure(
            MLDaemonError.remoteError("ModuleNotFoundError: No module named 'mlx_lm'")
        )
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })

        do {
            _ = try await service.correct(text: "text", modelRepo: "repo", pythonPath: "/tmp/python")
            XCTFail("Expected dependencyMissing error")
        } catch {
            guard case MLXCorrectionError.dependencyMissing(let dep, let command) = error else {
                return XCTFail("Expected dependencyMissing error")
            }
            XCTAssertEqual(dep, "mlx-lm")
            XCTAssertEqual(command, "uv add mlx-lm")
        }
    }

    /// Audit #40: a runtime error whose stack trace merely mentions the
    /// `mlx_lm` module path must NOT be misclassified as a missing dependency.
    func testCorrectDoesNotMisclassifyRuntimeErrorMentioningMLXLM() async {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .failure(
            MLDaemonError.remoteError(
                "RuntimeError: out of memory while running mlx_lm.generate at .../mlx_lm/utils.py"
            )
        )
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })

        do {
            _ = try await service.correct(text: "text", modelRepo: "repo", pythonPath: "/tmp/python")
            XCTFail("Expected correctionFailed, not dependencyMissing")
        } catch {
            guard case MLXCorrectionError.correctionFailed = error else {
                return XCTFail("Runtime error mentioning mlx_lm must map to correctionFailed, got \(error)")
            }
        }
    }

    /// Audit #40: the daemon loader wraps a genuine missing import as
    /// `mlx-lm import failed:` — that prefix must still trigger dependencyMissing.
    func testCorrectMapsLoaderImportFailurePrefix() async {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .failure(
            MLDaemonError.remoteError("mlx-lm import failed: No module named 'mlx_lm'")
        )
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })

        do {
            _ = try await service.correct(text: "text", modelRepo: "repo", pythonPath: "/tmp/python")
            XCTFail("Expected dependencyMissing")
        } catch {
            guard case MLXCorrectionError.dependencyMissing = error else {
                return XCTFail("Expected dependencyMissing, got \(error)")
            }
        }
    }

    /// Audit #40: a model-load failure must not be misread as a missing package.
    func testCorrectModelNotAvailableOfflineMapsToCorrectionFailed() async {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .failure(
            MLDaemonError.remoteError(
                "MLX model not available offline. Please open Settings to download it."
            )
        )
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })

        do {
            _ = try await service.correct(text: "text", modelRepo: "repo", pythonPath: "/tmp/python")
            XCTFail("Expected correctionFailed")
        } catch {
            guard case MLXCorrectionError.correctionFailed = error else {
                return XCTFail("Expected correctionFailed, got \(error)")
            }
        }
    }

    /// Audit #40: the structured Python marker is recognised directly.
    func testIsMLXDependencyMissingDetectsStructuredMarker() {
        XCTAssertTrue(MLXCorrectionService.isMLXDependencyMissing(
            #"{"success": false, "error": "...", "error_kind": "dependency_missing"}"#
        ))
    }

    func testIsMLXDependencyMissingIgnoresUnrelatedMention() {
        XCTAssertFalse(MLXCorrectionService.isMLXDependencyMissing(
            "Traceback: file .../mlx_lm/sample_utils.py line 10 ValueError: bad shape"
        ))
    }
    
    func testCorrectMapsScriptNotFoundError() async {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .failure(MLDaemonError.scriptNotFound)
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })
        
        do {
            _ = try await service.correct(text: "text", modelRepo: "repo", pythonPath: "/tmp/python")
            XCTFail("Expected scriptNotFound")
        } catch {
            XCTAssertEqual(error as? MLXCorrectionError, .scriptNotFound)
        }
    }
    
    func testCorrectMapsDaemonUnavailableError() async {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .failure(MLDaemonError.daemonUnavailable("down"))
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })
        
        do {
            _ = try await service.correct(text: "text", modelRepo: "repo", pythonPath: "/tmp/python")
            XCTFail("Expected daemonUnavailable")
        } catch {
            XCTAssertEqual(error as? MLXCorrectionError, .daemonUnavailable("down"))
        }
    }
    
    func testCorrectWrapsUnknownError() async {
        let daemon = MockMLDaemon()
        daemon.nextCorrectResult = .failure(NSError(domain: "test", code: 1))
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })
        
        do {
            _ = try await service.correct(text: "text", modelRepo: "repo", pythonPath: "/tmp/python")
            XCTFail("Expected correctionFailed")
        } catch {
            guard case MLXCorrectionError.correctionFailed(let message) = error else {
                return XCTFail("Expected correctionFailed")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }
    
    func testValidateSetupMissingPythonPathThrows() async {
        let daemon = MockMLDaemon()
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })
        
        do {
            _ = try await service.validateSetup(pythonPath: "/path/does/not/exist")
            XCTFail("Expected pythonNotFound")
        } catch {
            guard case MLXCorrectionError.pythonNotFound(let path) = error else {
                return XCTFail("Expected pythonNotFound")
            }
            XCTAssertEqual(path, "/path/does/not/exist")
        }
    }
    
    func testValidateSetupPingFailureThrows() async throws {
        let daemon = MockMLDaemon()
        daemon.pingResult = false
        
        // Create a real temporary file so fileExists passes
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())
        
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })
        
        do {
            _ = try await service.validateSetup(pythonPath: tempFile.path)
            XCTFail("Expected daemonUnavailable")
        } catch {
            XCTAssertEqual(error as? MLXCorrectionError, .daemonUnavailable("daemon not responding"))
        }
    }
    
    func testValidateSetupSucceedsWhenPathExistsAndPingOk() async throws {
        let daemon = MockMLDaemon()
        daemon.pingResult = true
        
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tempFile.path, contents: Data())
        
        let service = MLXCorrectionService(daemon: daemon, promptLoader: { nil })
        
        try await service.validateSetup(pythonPath: tempFile.path)
    }
}
