import Foundation
import WhisperKit
import Darwin

struct ModelEntry: Decodable { let path: String }
struct AudioCase: Decodable {
    let id: String
    let group: String
    let path: String
    let duration: Double
}

func elapsed(_ start: ContinuousClock.Instant) -> Double {
    let value = start.duration(to: .now).components
    return Double(value.seconds) + Double(value.attoseconds) / 1e18
}

@main
struct Benchmark {
    static func main() async throws {
        let processStart = ContinuousClock.now
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("Usage: WhisperBenchmark BASE MODEL_ID") }
        let base = URL(fileURLWithPath: args[1], isDirectory: true)
        let ident = args[2]
        let registry = try JSONDecoder().decode([String: ModelEntry].self, from: Data(contentsOf: base.appendingPathComponent("models.json")))
        guard let model = registry[ident] else { fatalError("Unknown model") }
        let corpus = try JSONDecoder().decode([AudioCase].self, from: Data(contentsOf: base.appendingPathComponent("corpus/manifest.json")))
        let output = base.appendingPathComponent("results/\(ident).jsonl")
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let file = try FileHandle(forWritingTo: output)
        defer { try? file.close() }

        func emit(_ payload: [String: Any]) throws {
            var event = payload
            event["model_id"] = ident
            var usage = rusage()
            _ = getrusage(RUSAGE_SELF, &usage)
            event["rss_peak_bytes"] = usage.ru_maxrss
            let data = try JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
            try file.write(contentsOf: data + Data([10]))
            var concise = event
            concise.removeValue(forKey: "text")
            print(String(data: try JSONSerialization.data(withJSONObject: concise), encoding: .utf8)!)
            fflush(stdout)
        }

        // Match production LocalWhisperService: local model folder, default
        // compute policy, transcribe task, automatic language, incremental input.
        let loadStart = ContinuousClock.now
        let kit = try await WhisperKit(WhisperKitConfig(modelFolder: model.path, verbose: false, download: false))
        var options = DecodingOptions()
        options.task = .transcribe
        options.language = nil
        func transcribe(_ item: AudioCase) async throws -> String {
            try await kit.transcribe(audioPath: item.path,
                                     audioInputOptions: AudioInputOptions(audioLoadingMode: .incremental),
                                     decodeOptions: options).map(\.text).joined(separator: " ")
        }
        try emit(["kind": "loaded", "load_seconds": elapsed(loadStart), "process_to_loaded_seconds": elapsed(processStart),
                  "settings": ["WhisperKit": "1.1.0", "language": "auto", "task": "transcribe", "audio": "incremental", "compute": "SDK default matching app"]])
        let start = ContinuousClock.now
        let firstText = try await transcribe(corpus[0])
        try emit(["kind": "first-use", "case": corpus[0].id, "seconds": elapsed(start),
                  "process_to_first_result_seconds": elapsed(processStart), "text": firstText])
        let speed = corpus.first { $0.group == "speed" }!
        _ = try await transcribe(speed)
        for repetition in 0..<5 {
            let start = ContinuousClock.now
            let text = try await transcribe(speed)
            try emit(["kind": "speed", "case": speed.id, "repetition": repetition, "seconds": elapsed(start),
                      "audio_seconds": speed.duration, "text": text])
        }
        var failures = 0
        for item in corpus where item.group != "speed" {
            let start = ContinuousClock.now
            do {
                let text = try await transcribe(item)
                try emit(["kind": "quality", "case": item.id, "group": item.group, "seconds": elapsed(start),
                          "audio_seconds": item.duration, "text": text])
            } catch {
                failures += 1
                try emit(["kind": "error", "case": item.id, "group": item.group, "error": String(describing: error)])
            }
        }
        try emit(["kind": "complete", "failures": failures])
        if failures > 0 { exit(1) }
    }
}
