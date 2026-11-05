import Foundation

enum DiagnosticStage: String, Codable, CaseIterable, Sendable {
    case microphoneStart, audioFinalization, audioValidation, runtimePreparation, audioConversion
    case voiceModelLoad, voiceInference, voicePipeline, formatting, writingCleanup, writingModelLoad
    case focusActivation, pasteConfirmation, clipboardRestore, historySave, stopToDelivery, total
    case voiceWorkerOperation, writingWorkerOperation
}

enum DiagnosticOutcome: String, Codable, Sendable {
    case completed, failed, cancelled, interrupted
}

enum DiagnosticEntry: String, Codable, Sendable { case recording, practice, fileImport, retry }
enum DiagnosticCache: String, Codable, Sendable { case cold, warm, unknown }
enum DiagnosticDelivery: String, Codable, Sendable { case copied, pasted, unverified, manual, none }
enum DiagnosticFailure: String, Codable, Sendable {
    case microphoneStart, noAudio, silence, voiceReadiness, processing, history, paste
}

struct DiagnosticSpan: Codable, Equatable, Sendable {
    var stage: DiagnosticStage
    var milliseconds: Double
    var outcome: DiagnosticOutcome
}

/// Operational metadata only. No transcript, audio, vocabulary, instructions,
/// selected reference, file path, window title, or raw exception message.
struct DiagnosticRecord: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var started: Date
    var finished: Date
    var build: String
    var system: String
    var architecture: String
    var entry: DiagnosticEntry
    var provider: String
    var voiceModel: String
    var writingModel: String?
    var modeID: UUID?
    var preferredInput: Bool
    var sampleRate: Double?
    var channelCount: UInt32?
    var outcome: DiagnosticOutcome
    var delivery: DiagnosticDelivery
    var voiceCache: DiagnosticCache = .unknown
    var writingCache: DiagnosticCache = .unknown
    var truncated = false
    var interrupted = false
    var failure: DiagnosticFailure?
    var spans: [DiagnosticSpan]
    var resources: [DiagnosticResource]

    static func modelIdentifier(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 128,
              value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"
                + "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-").contains($0) }),
              !value.hasPrefix("/"), !value.contains(".."), value.split(separator: "/").count <= 2 else { return nil }
        return value
    }
}

struct DiagnosticWindowEvent: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case requested, activationRequested, activated, spaceChanged, orderedFront, overlayShown
    }
    var date: Date
    var action: Action
    var build: String
    var windowNumber: Int
    var level: Int
    var behavior: UInt
    var applicationPolicy: Int
    var applicationActive: Bool
    var systemFullScreen: Bool
    var visible: Bool
    var key: Bool
    var onActiveSpace: Bool
    var frame: [Double]
}

struct DiagnosticArchive: Codable, Sendable {
    var schema = 1
    var sessions: [DiagnosticRecord] = []
    var windows: [DiagnosticWindowEvent] = []
}

struct DiagnosticSummary: Sendable {
    var count: Int
    var failures: Int
    var stages: [DiagnosticStage: (median: Double, p95: Double)]

    init(_ records: [DiagnosticRecord]) {
        count = records.count
        failures = records.filter { $0.outcome == .failed }.count
        stages = [:]
        for stage in DiagnosticStage.allCases {
            let values = records.compactMap { record -> Double? in
                let matching = record.spans.filter { $0.stage == stage && $0.outcome == .completed }
                return matching.isEmpty ? nil : matching.reduce(0) { $0 + $1.milliseconds }
            }.sorted()
            guard !values.isEmpty else { continue }
            stages[stage] = (Self.percentile(values, 0.5), Self.percentile(values, 0.95))
        }
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double {
        values[max(0, min(values.count - 1, Int(ceil(Double(values.count) * fraction)) - 1))]
    }
}
