import Foundation

@main
@MainActor
internal enum AudioWhisperEntryPoint {
    static func main() {
        guard CommandLine.arguments.contains("--diagnose-recording") else {
            AudioWhisperApp.main()
            return
        }
        Task {
            do {
                let report = await RecordingDiagnostics.snapshot()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                var data = try encoder.encode(report)
                data.append(0x0a)
                FileHandle.standardOutput.write(data)
                exit(EXIT_SUCCESS)
            } catch {
                FileHandle.standardError.write(Data("Recording diagnostics failed: \(error.localizedDescription)\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        dispatchMain()
    }
}
