import Foundation

/// Optional RPC metadata keeps compatibility with workers lacking diagnostics.
struct DiagnosticWorkerMetrics: Codable, Equatable, Sendable {
    var cache: DiagnosticCache
    var loadMilliseconds: Double
    var operationMilliseconds: Double
    var cpuSeconds: Double
    var peakResidentBytes: UInt64

    func record(writing: Bool) {
        guard let trace = DiagnosticInstrumentation.trace,
              [loadMilliseconds, operationMilliseconds, cpuSeconds].allSatisfy({ $0.isFinite && $0 >= 0 }),
              loadMilliseconds <= operationMilliseconds else { return }
        trace.cache(cache, writing: writing)
        trace.duration(writing ? .writingWorkerOperation : .voiceWorkerOperation, milliseconds: operationMilliseconds)
        if cache == .cold { trace.duration(writing ? .writingModelLoad : .voiceModelLoad, milliseconds: loadMilliseconds) }
        trace.workerResource(cpu: cpuSeconds, peak: peakResidentBytes)
    }
}

private enum DiagnosticResultKeys: String, CodingKey { case success, text, error, diagnostics }

// Diagnostic metadata is advisory. An older/future or malformed metrics
// payload must never turn a successful transcript into a decoding failure.
extension MLRPCResult.Transcribe {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DiagnosticResultKeys.self)
        success = try values.decode(Bool.self, forKey: .success)
        text = try values.decode(String.self, forKey: .text)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        diagnostics = try? values.decodeIfPresent(DiagnosticWorkerMetrics.self, forKey: .diagnostics)
    }
}

extension MLRPCResult.Correct {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: DiagnosticResultKeys.self)
        success = try values.decode(Bool.self, forKey: .success)
        text = try values.decode(String.self, forKey: .text)
        error = try values.decodeIfPresent(String.self, forKey: .error)
        diagnostics = try? values.decodeIfPresent(DiagnosticWorkerMetrics.self, forKey: .diagnostics)
    }
}
