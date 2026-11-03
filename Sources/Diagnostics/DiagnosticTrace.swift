import Foundation

/// Per-session ownership follows structured tasks. A completed trace rejects
/// late callbacks, so cancellation/retry cannot contaminate another session.
final class DiagnosticTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var record: DiagnosticRecord
    private var open: [UUID: (DiagnosticStage, TimeInterval)] = [:]
    private var closed = false
    let uptime: TimeInterval

    init(record: DiagnosticRecord, uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.record = record
        self.uptime = uptime
        sample()
    }

    func begin(_ stage: DiagnosticStage) -> UUID {
        lock.withLock {
            let token = UUID()
            if !closed, open.count < 32 { open[token] = (stage, ProcessInfo.processInfo.systemUptime) }
            return token
        }
    }

    func end(_ token: UUID, outcome: DiagnosticOutcome = .completed) {
        lock.withLock {
            guard !closed, let (stage, start) = open.removeValue(forKey: token) else { return }
            append(stage, milliseconds: (ProcessInfo.processInfo.systemUptime - start) * 1_000, outcome: outcome)
        }
    }

    private func append(_ stage: DiagnosticStage, milliseconds: Double, outcome: DiagnosticOutcome = .completed) {
        guard milliseconds.isFinite, milliseconds >= 0 else { return }
        if record.spans.count < 64 {
            record.spans.append(.init(stage: stage, milliseconds: milliseconds, outcome: outcome))
        } else { record.truncated = true }
    }

    func cache(_ value: DiagnosticCache, writing: Bool = false) {
        lock.withLock {
            guard !closed else { return }
            if writing { record.writingCache = value } else { record.voiceCache = value }
        }
    }

    func duration(_ stage: DiagnosticStage, milliseconds: Double) {
        lock.withLock { if !closed { append(stage, milliseconds: milliseconds) } }
    }

    func failure(_ value: DiagnosticFailure) {
        lock.withLock { if !closed, record.failure == nil { record.failure = value } }
    }

    func interruption() { lock.withLock { if !closed { record.interrupted = true } } }

    func input(rate: Double, channels: UInt32) {
        lock.withLock {
            guard !closed, rate.isFinite, rate > 0 else { return }
            record.sampleRate = rate
            record.channelCount = channels
        }
    }

    func sample() {
        guard let sample = DiagnosticResource.application(since: uptime) else { return }
        lock.withLock {
            guard !closed else { return }
            if record.resources.count < 128 {
                record.resources.append(sample)
            } else {
                if let index = record.resources.lastIndex(where: { $0.scope == .application }) {
                    record.resources[index] = sample
                }
                record.truncated = true
            }
        }
    }

    func workerResource(cpu: Double, peak: UInt64) {
        lock.withLock {
            guard !closed else { return }
            let resource = DiagnosticResource(scope: .modelWorker,
                elapsedMilliseconds: max(0, (ProcessInfo.processInfo.systemUptime - uptime) * 1_000),
                cpuSeconds: cpu, residentBytes: peak, thermalState: ProcessInfo.processInfo.thermalState.rawValue,
                cpuIsCumulative: false, memoryIsPeak: true)
            if record.resources.count < 128 {
                record.resources.append(resource)
            } else {
                let index = record.resources.dropFirst().firstIndex { $0.scope == .application } ?? 127
                record.resources.remove(at: index)
                record.resources.append(resource)
                record.truncated = true
            }
        }
    }

    func finish(_ outcome: DiagnosticOutcome, delivery: DiagnosticDelivery) -> DiagnosticRecord? {
        sample()
        return lock.withLock {
            guard !closed else { return nil }
            let now = ProcessInfo.processInfo.systemUptime
            for (_, (stage, start)) in open {
                append(stage, milliseconds: (now - start) * 1_000, outcome: outcome)
            }
            open = [:]
            append(.total, milliseconds: (now - uptime) * 1_000, outcome: outcome)
            record.outcome = outcome
            record.delivery = delivery
            record.finished = Date()
            closed = true
            return record
        }
    }
}

enum DiagnosticInstrumentation {
    @TaskLocal static var trace: DiagnosticTrace?

    static func measure<T>(_ stage: DiagnosticStage, _ operation: () async throws -> T) async rethrows -> T {
        let token = trace?.begin(stage)
        do {
            let value = try await operation()
            if let token { trace?.end(token) }
            return value
        } catch {
            if let token { trace?.end(token, outcome: error is CancellationError ? .cancelled : .failed) }
            throw error
        }
    }
}
