import Foundation
import os.log

internal enum ParakeetError: Error, LocalizedError, Equatable {
    case pythonNotFound(path: String)
    case scriptNotFound
    case transcriptionFailed(String)
    case invalidResponse(String)
    case dependencyMissing(String, installCommand: String)
    case processTimedOut(TimeInterval)
    case modelNotReady
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .pythonNotFound(let path):
            return "Python runtime not available at: \(path)\n\nFix:\n• Open Settings ▸ Parakeet ▸ Install/Update Dependencies with uv"
        case .scriptNotFound:
            return "Parakeet transcription script not found in app bundle"
        case .transcriptionFailed(let message):
            return "Parakeet transcription failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from Parakeet: \(message)"
        case .dependencyMissing(let dependency, _):
            return "\(dependency) is not installed\n\nFix: Open Settings ▸ Parakeet ▸ Install/Update Dependencies with uv"
        case .processTimedOut(let timeout):
            return "Transcription timed out after \(timeout) seconds\n\nTry with a shorter audio file or check system resources"
        case .modelNotReady:
            return "Parakeet model not downloaded. Open Settings ▸ Parakeet to download it."
        case .emptyAudio:
            return "No audio detected in the recording. Try speaking louder or closer to the microphone."
        }
    }
}

internal class ParakeetService {
    static let shared = ParakeetService()

    private let logger = Logger(subsystem: "com.audiowhisper.app", category: "ParakeetService")
    private let daemon: MLDaemonManager

    init(daemon: MLDaemonManager = .shared) { self.daemon = daemon }

    func transcribe(audioFileURL: URL, pythonPath: String? = nil) async throws -> String {
        try await transcribe(audioFileURL: audioFileURL, pythonPath: pythonPath, model: safeSelectedParakeetModel)
    }

    func transcribe(audioFileURL: URL, pythonPath _: String?, model: ParakeetModel) async throws -> String {
        // Step 0: Do not download here; just verify model cache exists
        guard await isModelCached(model: model) else {
            throw ParakeetError.modelNotReady
        }

        // Step 1: Process audio with Swift AudioProcessor to create raw PCM data
        let pcmDataURL = try await processAudioToRawPCM(audioFileURL: audioFileURL)

        return try await transcribePreparedPCM(pcmDataURL, repo: model.rawValue)
    }

    func transcribePreparedPCM(_ pcmDataURL: URL, repo: String) async throws -> String {
        // Step 2: Call Python with the raw PCM data.
        //
        // The daemon runs in a SEPARATE subprocess that keeps reading the PCM
        // file even if this Swift task is cancelled or times out. Deleting the
        // file on a plain `defer` (which fires the instant this function
        // returns) would yank it out from under that subprocess. Instead the
        // daemon call runs in a detached, non-cancellable task whose completion
        // — success, failure, OR timeout — is what triggers deletion.
        let pcmPath = pcmDataURL.path
        let daemonRef = daemon
        let loggerRef = logger
        let daemonTask = Task.detached(priority: .userInitiated) { () -> String in
            defer {
                // Delete only after the daemon request has fully finished, so
                // the subprocess can never read a file that no longer exists.
                try? FileManager.default.removeItem(atPath: pcmPath)
            }
            do {
                let text = try await daemonRef.transcribe(repo: repo, pcmPath: pcmPath)
                loggerRef.info("Parakeet transcription successful")
                return text
            } catch {
                loggerRef.error("Parakeet transcription error: \(error.localizedDescription)")
                throw error
            }
        }

        return try await cancellableValue(of: daemonTask)
    }

    /// Default Parakeet model used when the stored `selectedParakeetModel` value
    /// is missing or doesn't match a known `ParakeetModel` case. Mirrors
    /// `AppDefaults.selectedParakeetModel`.
    static let defaultModel: ParakeetModel = .v2English

    /// Validates the persisted `selectedParakeetModel` against the
    /// `ParakeetModel` enum and falls back to `defaultModel` when the stored
    /// value is empty or no longer matches a known case. Prevents stale or
    /// hand-edited preferences from pointing the MLX daemon at a repo string
    /// that the app no longer recognises.
    var safeSelectedParakeetModel: ParakeetModel {
        // `AppDefaults.selectedParakeetModel` already validates against the enum and
        // falls back to `.v2English` (== `defaultModel`).
        AppDefaults.selectedParakeetModel
    }

    private var selectedRepo: String {
        safeSelectedParakeetModel.rawValue
    }

    /// Checks if the model is cached on disk.
    /// This is an async function to avoid blocking the main thread with file I/O operations.
    func isModelCached(model: ParakeetModel? = nil) async -> Bool {
        let repo = model?.rawValue ?? selectedRepo
        // Run file I/O on a background thread to avoid blocking main thread
        return await Task.detached(priority: .userInitiated) {
            HuggingFaceCache.completeSnapshot(in: HuggingFaceCache.modelDirectory(repo: repo))
        }.value
    }

    private func processAudioToRawPCM(audioFileURL: URL) async throws -> URL {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("audio_pcm_\(UUID()).raw")
        let conversion = Task.detached(priority: .userInitiated) {
            try RawPCMConverter.convert(input: audioFileURL, output: output)
            return output
        }
        return try await withTaskCancellationHandler {
            let result = try await conversion.value
            do { try Task.checkCancellation() } catch {
                try? FileManager.default.removeItem(at: result)
                throw error
            }
            return result
        } onCancel: {
            conversion.cancel()
        }
    }

    func validateSetup(pythonPath _: String? = nil) async throws {
        guard await isModelCached() else {
            throw ParakeetError.modelNotReady
        }

        do {
            try await daemon.warmup(type: .parakeet, repo: selectedRepo)
        } catch {
            logger.error("Parakeet warmup failed: \(error.localizedDescription)")
            throw ParakeetError.transcriptionFailed("Parakeet daemon unavailable: \(error.localizedDescription)")
        }
    }
}
