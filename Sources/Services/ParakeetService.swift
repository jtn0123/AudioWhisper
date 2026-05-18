import Foundation
import os.log
import AudioToolbox

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

internal struct ParakeetResponse: Codable {
    let text: String
    let success: Bool
    let error: String?
}

internal class ParakeetService {
    static let shared = ParakeetService()

    private let logger = Logger(subsystem: "com.audiowhisper.app", category: "ParakeetService")
    private let daemon = MLDaemonManager.shared

    func transcribe(audioFileURL: URL, pythonPath _: String? = nil) async throws -> String {
        // Step 0: Do not download here; just verify model cache exists
        guard await isModelCached() else {
            throw ParakeetError.modelNotReady
        }

        // Step 1: Process audio with Swift AudioProcessor to create raw PCM data
        let pcmDataURL = try await processAudioToRawPCM(audioFileURL: audioFileURL)

        // Step 2: Call Python with the raw PCM data.
        //
        // The daemon runs in a SEPARATE subprocess that keeps reading the PCM
        // file even if this Swift task is cancelled or times out. Deleting the
        // file on a plain `defer` (which fires the instant this function
        // returns) would yank it out from under that subprocess. Instead the
        // daemon call runs in a detached, non-cancellable task whose completion
        // — success, failure, OR timeout — is what triggers deletion.
        let pcmPath = pcmDataURL.path
        let repo = selectedRepo
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

        // Await the detached task. If THIS task is cancelled the await throws
        // CancellationError, but the detached task keeps running and cleans up
        // the PCM file itself once the daemon is genuinely done with it.
        return try await withTaskCancellationHandler {
            try await daemonTask.value
        } onCancel: {
            // Do not delete the file here — the detached task still owns it.
        }
    }

    /// Default Parakeet model used when the stored `selectedParakeetModel` value
    /// is missing or doesn't match a known `ParakeetModel` case. Mirrors
    /// `AppDefaults.selectedParakeetModel`.
    static let defaultModel: ParakeetModel = .v3Multilingual

    /// Validates the persisted `selectedParakeetModel` against the
    /// `ParakeetModel` enum and falls back to `defaultModel` when the stored
    /// value is empty or no longer matches a known case. Prevents stale or
    /// hand-edited preferences from pointing the MLX daemon at a repo string
    /// that the app no longer recognises.
    var safeSelectedParakeetModel: ParakeetModel {
        // `AppDefaults.selectedParakeetModel` already validates against the enum and
        // falls back to `.v3Multilingual` (== `defaultModel`).
        AppDefaults.selectedParakeetModel
    }

    private var selectedRepo: String {
        safeSelectedParakeetModel.rawValue
    }

    /// Checks if the model is cached on disk.
    /// This is an async function to avoid blocking the main thread with file I/O operations.
    private func isModelCached() async -> Bool {
        let repo = selectedRepo
        // Run file I/O on a background thread to avoid blocking main thread
        return await Task.detached(priority: .userInitiated) {
            let escaped = repo.replacingOccurrences(of: "/", with: "--")
            let base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cache/huggingface/hub/models--\(escaped)")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir), isDir.boolValue else { return false }
            let refsMain = base.appendingPathComponent("refs/main")

            // Validate file size before reading to prevent memory issues
            // The refs/main file should be tiny (just a SHA hash, typically 40-64 bytes)
            // If it's larger than 1KB, something is wrong - don't read it
            let maxRefsFileSize: Int64 = 1024
            guard let fileSize = try? FileManager.default.attributesOfItem(atPath: refsMain.path)[.size] as? Int64,
                  fileSize <= maxRefsFileSize else {
                return false
            }

            // The file holds a Hugging Face commit hash; require pure hex.
            let rawRev = try? String(contentsOf: refsMain, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let rev = rawRev, !rev.isEmpty,
                  rev.allSatisfy({ $0.isHexDigit }) else {
                return false
            }
            // Resolve the snapshot directory by matching `rev` against the
            // actual directory listing rather than interpolating it into a
            // path: `snap` is built only from a filesystem-returned name.
            let snapshotsDir = base.appendingPathComponent("snapshots")
            let snapshotEntries = (try? FileManager.default.contentsOfDirectory(atPath: snapshotsDir.path)) ?? []
            guard let matchedSnapshot = snapshotEntries.first(where: { $0 == rev }) else { return false }
            let snap = snapshotsDir.appendingPathComponent(matchedSnapshot)
            guard FileManager.default.fileExists(atPath: snap.path, isDirectory: &isDir), isDir.boolValue else { return false }
            // Look for at least one weights file under snapshot or blobs
            let snapFiles = (try? FileManager.default.contentsOfDirectory(atPath: snap.path)) ?? []
            let blobsPath = base.appendingPathComponent("blobs").path
            let blobsFiles = (try? FileManager.default.contentsOfDirectory(atPath: blobsPath)) ?? []
            let hasWeights = snapFiles.contains { $0.hasSuffix(".safetensors") }
                || blobsFiles.contains { $0.hasSuffix(".safetensors") }
            return hasWeights
        }.value
    }
    
    private func processAudioToRawPCM(audioFileURL: URL) async throws -> URL {
        // Create temporary file for raw PCM data
        let tempPCMURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_pcm_\(UUID().uuidString).raw")
        
        do {
            // Use AudioProcessor.swift logic directly
            let samples = try loadAudio(url: audioFileURL, samplingRate: 16000)

            // Guard against empty / near-empty audio: writing a 0-byte .raw
            // file just hands the daemon nothing to transcribe. 1600 samples
            // == 0.1s at 16kHz — anything shorter is effectively silence.
            let minimumSamples = 1600
            guard samples.count >= minimumSamples else {
                throw ParakeetError.emptyAudio
            }

            // Write raw float32 data
            let data = samples.withUnsafeBytes { Data($0) }
            try data.write(to: tempPCMURL)

            return tempPCMURL

        } catch let error as ParakeetError {
            // Preserve specific domain errors (e.g. .emptyAudio) intact.
            throw error
        } catch {
            throw ParakeetError.transcriptionFailed("Audio processing failed: \(error.localizedDescription)")
        }
    }
    
    // Audio processing function from AudioProcessor.swift
    private func loadAudio(url: URL, samplingRate: Int) throws -> [Float] {
        var extAudioFile: ExtAudioFileRef?
        
        // Open the audio file
        var status = ExtAudioFileOpenURL(url as CFURL, &extAudioFile)
        guard status == noErr, let extFile = extAudioFile else {
            throw ParakeetError.transcriptionFailed("Failed to open audio file: \(status)")
        }
        defer { ExtAudioFileDispose(extFile) }
        
        // Get file's original format and length
        var fileFormat = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileGetProperty(extFile, kExtAudioFileProperty_FileDataFormat, &propertySize, &fileFormat)
        guard status == noErr else {
            throw ParakeetError.transcriptionFailed("Failed to get audio format: \(status)")
        }
        
        var fileLengthFrames: Int64 = 0
        propertySize = UInt32(MemoryLayout<Int64>.size)
        status = ExtAudioFileGetProperty(extFile, kExtAudioFileProperty_FileLengthFrames, &propertySize, &fileLengthFrames)
        guard status == noErr else {
            throw ParakeetError.transcriptionFailed("Failed to get audio length: \(status)")
        }
        
        // Define client format: mono, float32, target sample rate, interleaved/packed
        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: Float64(samplingRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        
        propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileSetProperty(extFile, kExtAudioFileProperty_ClientDataFormat, propertySize, &clientFormat)
        guard status == noErr else {
            throw ParakeetError.transcriptionFailed("Failed to set audio format: \(status)")
        }
        
        // Estimate client length for preallocation
        let fileSampleRate = fileFormat.mSampleRate
        let duration = Double(fileLengthFrames) / fileSampleRate
        let estimatedClientFrames = Int(duration * Double(samplingRate) + 0.5)
        var samples: [Float] = []
        samples.reserveCapacity(estimatedClientFrames)
        
        // Read in chunks until EOF
        let bufferFrameSize = 4096
        var buffer = [Float](repeating: 0, count: bufferFrameSize)
        
        while true {
            var numFrames = UInt32(bufferFrameSize)
            
            let audioBuffer = buffer.withUnsafeMutableBytes { bytes in
                AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(bufferFrameSize * MemoryLayout<Float>.size),
                    mData: bytes.baseAddress
                )
            }
            var audioBufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
            
            status = ExtAudioFileRead(extFile, &numFrames, &audioBufferList)
            guard status == noErr else {
                throw ParakeetError.transcriptionFailed("Failed to read audio data: \(status)")
            }
            
            if numFrames == 0 {
                break  // EOF
            }

            // Defensive bounds check - ExtAudioFileRead should never return more than requested
            let framesToCopy = min(Int(numFrames), bufferFrameSize)
            samples.append(contentsOf: buffer[0..<framesToCopy])
        }
        
        return samples
    }
    
    func validateSetup(pythonPath _: String? = nil) async throws {
        guard await isModelCached() else {
            throw ParakeetError.modelNotReady
        }

        do {
            try await daemon.warmup(type: "parakeet", repo: selectedRepo)
        } catch {
            logger.error("Parakeet warmup failed: \(error.localizedDescription)")
            throw ParakeetError.transcriptionFailed("Parakeet daemon unavailable: \(error.localizedDescription)")
        }
    }
}
