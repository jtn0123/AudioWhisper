import Foundation

enum PublicAutomationError: String, LocalizedError {
    case arguments = "Invalid command. Use --help for supported commands and options."
    case mode = "That saved dictation mode does not exist. Use modes to list its ID."
    case assets = "Install the selected voice model and local runtime in the app before using automation."
    case file = "Choose a readable local audio file smaller than 256 MB."
    case scope = "MCP files must be inside the explicitly allowed directory, including resolved symlinks."
    var errorDescription: String? { rawValue }
}

struct PublicTranscription: Codable, Sendable {
    let text: String
    let originalText: String
    let writingOutcome: String
    let audioDuration: TimeInterval?
}

enum AutomationCommand: Equatable {
    case help, version, status, modes
    case transcribe(path: String, mode: UUID?, json: Bool)
    case mcp(directory: String)

    static func parse(_ arguments: [String]) throws -> Self? {
        guard let first = arguments.first else { return nil }
        switch first {
        case "--help", "-h": guard arguments.count == 1 else { throw PublicAutomationError.arguments }; return .help
        case "--version": guard arguments.count == 1 else { throw PublicAutomationError.arguments }; return .version
        case "status", "--diagnose-recording":
            guard arguments.count == 1 else { throw PublicAutomationError.arguments }; return .status
        case "modes": guard arguments.count == 1 else { throw PublicAutomationError.arguments }; return .modes
        case "mcp":
            guard arguments.count == 3, arguments[1] == "--allow-directory" else { throw PublicAutomationError.arguments }
            return .mcp(directory: arguments[2])
        case "transcribe": return try parseTranscription(Array(arguments.dropFirst()))
        default: throw PublicAutomationError.arguments
        }
    }

    private static func parseTranscription(_ arguments: [String]) throws -> Self {
        guard let path = arguments.first, !path.hasPrefix("--") else { throw PublicAutomationError.arguments }
        var remaining = Array(arguments.dropFirst())
        var json = false
        var mode: UUID?
        while let option = remaining.first {
            remaining.removeFirst()
            if option == "--json", !json {
                json = true
            } else if option == "--mode", mode == nil, let raw = remaining.first, let id = UUID(uuidString: raw) {
                mode = id
                remaining.removeFirst()
            } else { throw PublicAutomationError.arguments }
        }
        return .transcribe(path: path, mode: mode, json: json)
    }
}

@MainActor
struct PublicAutomationServices {
    var runtimeReady: (RebuildModelSelection) async -> Bool
    var modelInstalled: (RebuildModelSelection) async -> Bool
    var transcribe: (URL, DictationModeSettings) async throws -> TranscriptionResult

    static var live: Self {
        let setup = RebuildSetupServices.live
        return .init(runtimeReady: setup.runtimeReady, modelInstalled: setup.modelInstalled,
                     transcribe: { try await PublicAutomation.installedTranscription($0, settings: $1) })
    }
}

@MainActor
enum PublicAutomation {
    static let help = """
        AudioWhisper — local automation
        --help | --version | status | modes
        transcribe <audio-file> [--mode <saved-mode-UUID>] [--json]
        mcp --allow-directory <audio-directory>

        Uses installed models only. Does not record, read external context,
        change the clipboard, paste, or add library records.
        Deep links: audiowhisper://open?page=record|library|meetings|models|writing|preferences
        """

    static func transcribe(path: String, modeID: UUID?, allowedDirectory: URL? = nil,
                           services: PublicAutomationServices? = nil) async throws -> PublicTranscription {
        let url = try audioURL(path: path, allowedDirectory: allowedDirectory)
        let mode = modeID.flatMap { id in AppDefaults.savedDictationModes.first { $0.id == id } }
        if modeID != nil && mode == nil { throw PublicAutomationError.mode }
        var settings = mode?.settings ?? AppDefaults.currentDictationSettings
        settings.writing.contextSource = .none
        let selection = RebuildModelSelection(provider: settings.provider, whisper: settings.whisper, parakeet: settings.parakeet)
        let setup = services ?? .live
        guard await setup.runtimeReady(selection), await setup.modelInstalled(selection) else {
            throw PublicAutomationError.assets
        }
        try Task.checkCancellation()
        let result = try await setup.transcribe(url, settings)
        try Task.checkCancellation()
        let outcome: String
        switch result.correctionOutcome {
        case .applied: outcome = "applied"
        case .rejected: outcome = "rejected_original_preserved"
        case .failed: outcome = "unavailable_original_preserved"
        default: outcome = "off"
        }
        return PublicTranscription(text: result.text, originalText: result.originalText,
                                   writingOutcome: outcome, audioDuration: result.audioDuration)
    }

    static func installedTranscription(_ url: URL, settings: DictationModeSettings,
                                       pipeline supplied: TranscriptionPipeline? = nil) async throws -> TranscriptionResult {
        let needsPython = settings.provider == .parakeet || settings.cleanup == .localMLX
        let python = needsPython ? try await UvBootstrap.installedPython() : nil
        if settings.cleanup == .localMLX, !MLXModelManager.shared.isModelCachedOnDisk(repo: settings.cleanupModel) {
            throw PublicAutomationError.assets
        }
        let daemon = MLDaemonManager(pythonExecutable: python, allowsRuntimePreparation: false)
        let prepare: () async throws -> URL = {
            guard let python else { throw PublicAutomationError.assets }
            return python
        }
        let pipeline = supplied ?? TranscriptionPipeline(
            speechService: SpeechToTextService(parakeetService: ParakeetService(daemon: daemon), preparePython: prepare),
            correctionService: SemanticCorrectionService(
                mlxService: MLXCorrectionService(daemon: daemon), preparePython: prepare))
        // Hold the caller's inference reservation through actual worker cleanup.
        // Cancellation reaps this request's private daemon; no shared app job is affected.
        let worker = Task { try await pipeline.transcribe(audioURL: url, config: settings.pipeline()) }
        do {
            let result = try await withTaskCancellationHandler { try await worker.value } onCancel: {
                Task { await daemon.shutdown() }
            }
            await daemon.shutdown()
            return result
        } catch { await daemon.shutdown(); throw error }
    }

    static func directory(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard url.path != "/", FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { throw PublicAutomationError.scope }
        return url
    }

    static func audioURL(path: String, allowedDirectory: URL?) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        if let root = allowedDirectory, !url.path.hasPrefix(root.path + "/") { throw PublicAutomationError.scope }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 268_435_456,
              FileManager.default.isReadableFile(atPath: url.path) else { throw PublicAutomationError.file }
        return url
    }
}
