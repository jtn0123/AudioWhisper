import Foundation
import os.log

internal enum MLXCorrectionError: Error, LocalizedError, Equatable {
    case pythonNotFound(path: String)
    case scriptNotFound
    case correctionFailed(String)
    case invalidResponse(String)
    case dependencyMissing(String, installCommand: String)
    case processTimedOut(TimeInterval)
    case daemonUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound(let path):
            return "Python executable not found at: \(path)\n\nFix:\n• Open Settings ▸ Local LLM ▸ Install/Update Dependencies with uv"
        case .scriptNotFound:
            return "MLX correction script not found in app bundle"
        case .correctionFailed(let message):
            return "MLX correction failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from MLX correction: \(message)"
        case .dependencyMissing(let dependency, let installCommand):
            return "\(dependency) is not installed\n\nFix: Run: \(installCommand)\nOr open Settings ▸ Local LLM ▸ Install/Update Dependencies with uv"
        case .processTimedOut(let timeout):
            return "Correction timed out after \(timeout) seconds\n\nTry shorter text or check system resources"
        case .daemonUnavailable(let reason):
            return "ML daemon unavailable: \(reason)\n\nTry restarting the app"
        }
    }
}

internal protocol MLDaemonManaging {
    func correct(repo: String, text: String, prompt: String?) async throws -> String
    func ping() async -> Bool
}

extension MLDaemonManager: MLDaemonManaging {}

internal final class MLXCorrectionService {
    private let logger = Logger(subsystem: "com.audiowhisper.app", category: "MLXCorrectionService")
    private let daemon: MLDaemonManaging
    private let promptLoader: () -> String?

    init(daemon: MLDaemonManaging = MLDaemonManager.shared,
         promptLoader: @escaping () -> String? = MLXCorrectionService.loadSystemPrompt) {
        self.daemon = daemon
        self.promptLoader = promptLoader
    }

    func correct(text: String, modelRepo: String, pythonPath: String, systemPrompt: String? = nil) async throws -> String {
        // pythonPath is kept for API compatibility but daemon manages its own Python

        // Use provided prompt, or fall back to user's custom file, or nil for daemon default
        let prompt = systemPrompt ?? promptLoader()

        do {
            let result = try await daemon.correct(repo: modelRepo, text: text, prompt: prompt)
            return result
        } catch let error as MLDaemonError {
            // Map daemon errors to MLXCorrectionError for compatibility
            switch error {
            case .scriptNotFound:
                throw MLXCorrectionError.scriptNotFound
            case .daemonUnavailable(let reason):
                throw MLXCorrectionError.daemonUnavailable(reason)
            case .invalidResponse(let reason):
                throw MLXCorrectionError.invalidResponse(reason)
            case .remoteError(let message):
                if Self.isMLXDependencyMissing(message) {
                    throw MLXCorrectionError.dependencyMissing("mlx-lm", installCommand: "uv add mlx-lm")
                }
                throw MLXCorrectionError.correctionFailed(message)
            case .restartLimitReached:
                throw MLXCorrectionError.daemonUnavailable("restart limit reached")
            case .writeFailed:
                throw MLXCorrectionError.daemonUnavailable("failed to communicate with daemon")
            case .timeout:
                throw MLXCorrectionError.daemonUnavailable("request timed out")
            }
        } catch {
            // Skip logging in tests to reduce console noise
            if !AppEnvironment.isRunningTests {
                logger.error("MLX correction error: \(error.localizedDescription)")
            }
            throw MLXCorrectionError.correctionFailed(error.localizedDescription)
        }
    }

    // Cache invalidation is a no-op since daemon handles model loading
    func invalidateCache(for pythonPath: String? = nil) {
        // No-op: daemon manages model caching internally
    }

    func validateSetup(pythonPath: String) async throws {
        // Validate Python path exists (for settings UI feedback)
        guard FileManager.default.fileExists(atPath: pythonPath) else {
            throw MLXCorrectionError.pythonNotFound(path: pythonPath)
        }

        // Use daemon ping to verify the daemon is healthy
        let isHealthy = await daemon.ping()
        if !isHealthy {
            throw MLXCorrectionError.daemonUnavailable("daemon not responding")
        }
    }

    // MARK: - Private Helpers

    /// Decides whether a daemon `remoteError` message describes a genuinely
    /// missing `mlx-lm` package rather than an unrelated runtime failure that
    /// merely mentions the module (audit #40).
    ///
    /// A bare `contains("mlx_lm")` / `contains("ModuleNotFoundError")` matched
    /// any stack trace, OOM, or model-load error and wrongly told the user to
    /// install an already-installed package. We now require BOTH:
    ///   1. A genuine import-failure signal — either the daemon's structured
    ///      `error_kind=dependency_missing` marker, the daemon loader's
    ///      `mlx-lm import failed:` prefix, or an explicit
    ///      `ModuleNotFoundError`/`ImportError`.
    ///   2. The error to actually concern the `mlx_lm` / `mlx-lm` module.
    static func isMLXDependencyMissing(_ message: String) -> Bool {
        // Structured marker emitted by the Python side for this exact case.
        if message.contains("\"error_kind\": \"dependency_missing\"")
            || message.contains("\"error_kind\":\"dependency_missing\"") {
            return true
        }

        let mentionsMLX = message.contains("mlx_lm") || message.contains("mlx-lm")
        guard mentionsMLX else { return false }

        // The daemon loader wraps a missing-module import as exactly this.
        if message.contains("mlx-lm import failed:") {
            return true
        }

        // A genuine missing-module Python error for the mlx_lm module.
        let isModuleError = message.contains("ModuleNotFoundError")
            || message.contains("ImportError")
        return isModuleError
    }

    /// Maximum size of the user's custom MLX system prompt. Load-bearing —
    /// anything larger is rejected because a multi-MB prompt would bloat every
    /// request payload and is almost certainly a misconfigured file.
    private static let maxSystemPromptBytes = 64 * 1024

    private static func loadSystemPrompt() -> String? {
        guard let promptsDir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("AudioWhisper/prompts", isDirectory: true) else {
            return nil
        }

        let promptPath = promptsDir.appendingPathComponent("local_mlx_prompt.txt")
        guard FileManager.default.fileExists(atPath: promptPath.path) else {
            return nil
        }

        // M7: enforce a size cap before reading so a huge prompt file can't
        // slip into every JSON-RPC payload.
        if let attrs = try? FileManager.default.attributesOfItem(atPath: promptPath.path),
           let size = (attrs[.size] as? NSNumber)?.int64Value, size > Int64(maxSystemPromptBytes) {
            Logger.app.warning("MLX system prompt exceeds \(maxSystemPromptBytes) bytes (\(size)); ignoring")
            return nil
        }

        return decodePromptFile(at: promptPath)
    }

    /// Reads `promptPath` as utf8, falling back to utf16 then a utf8 decode of
    /// the raw bytes. Each fallback logs a warning so a mis-encoded prompt is
    /// observable in Console.app rather than silently producing nil.
    private static func decodePromptFile(at promptPath: URL) -> String? {
        if let utf8 = try? String(contentsOf: promptPath, encoding: .utf8) {
            return utf8
        }
        if let utf16 = try? String(contentsOf: promptPath, encoding: .utf16) {
            Logger.app.warning("MLX system prompt decoded as utf16 fallback")
            return utf16
        }
        if let data = try? Data(contentsOf: promptPath),
           let recovered = String(bytes: data, encoding: .utf8) {
            Logger.app.warning("MLX system prompt decoded via raw utf8 bytes fallback")
            return recovered
        }
        Logger.app.warning("MLX system prompt could not be decoded as utf8 or utf16")
        return nil
    }
}
