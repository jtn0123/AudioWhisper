import Foundation
import Darwin

@main
@MainActor
internal enum AudioWhisperEntryPoint {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard !arguments.isEmpty else {
            RebuildApp.main()
            return
        }
        // Preserve the protocol/output pipe; vendor libraries may log to stdout.
        let descriptor = dup(STDOUT_FILENO)
        guard descriptor >= 0 else { exit(EX_IOERR) }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        dup2(STDERR_FILENO, STDOUT_FILENO)
        Task { exit(await execute(arguments, output: output)) }
        dispatchMain()
    }

    static func execute(_ arguments: [String], output: FileHandle) async -> Int32 {
        do {
            guard let command = try AutomationCommand.parse(arguments) else { return EXIT_SUCCESS }
            switch command {
            case .help: output.write(Data((PublicAutomation.help + "\n").utf8))
            case .version: output.write(Data((VersionInfo.displayVersion + "\n").utf8))
            case .status: try write(await RebuildDiagnostics.snapshot(), to: output)
            case .modes:
                let modes = AppDefaults.savedDictationModes.map { ["id": $0.id.uuidString, "name": $0.name] }
                try write(modes, to: output)
            case .transcribe(let path, let mode, let json):
                let result = try await PublicAutomation.transcribe(path: path, modeID: mode)
                if json { try write(result, to: output) } else { output.write(Data((result.text + "\n").utf8)) }
            case .mcp(let directory):
                let server = PublicMCPServer(directory: try PublicAutomation.directory(directory), write: { output.write($0) })
                await PublicMCPTransport.run(server)
            }
            return EXIT_SUCCESS
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            return EXIT_FAILURE
        }
    }

    private static func write(_ value: some Encodable, to output: FileHandle) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0a)
        output.write(data)
    }
}
