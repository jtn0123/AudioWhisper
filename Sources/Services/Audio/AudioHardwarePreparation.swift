import Foundation

enum AudioPreparationError: LocalizedError {
    case busy, timedOut

    var errorDescription: String? {
        switch self {
        case .busy: return "The microphone is still connecting. Wait a moment before trying again."
        case .timedOut:
            return "The microphone took too long to connect. Reconnect it; if it stays stuck, quit and reopen AudioWhisper."
        }
    }
}

/// HAL initialization can block inside macOS. Keep it off the UI thread, allow
/// cancellation/timeouts, and never accumulate more work behind a stalled call.
/// Mutable state is protected by locks; only the worker owns the prepared value
/// until the continuation transfers it to its caller.
final class AudioHardwarePreparation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.audiowhisper.audio-preparation", qos: .userInitiated)
    private var workerInFlight = false

    var isInFlight: Bool {
        lock.lock()
        defer { lock.unlock() }
        return workerInFlight
    }

    func run(timeout: TimeInterval = 4, operation: @escaping @Sendable () throws -> Value) async throws -> Value {
        let request = Request<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard request.register(continuation) else { return }
                lock.lock()
                guard !workerInFlight else {
                    lock.unlock()
                    request.finish(.failure(AudioPreparationError.busy))
                    return
                }
                workerInFlight = true
                lock.unlock()
                queue.async {
                    let result = Result { try operation() }
                    self.lock.lock()
                    self.workerInFlight = false
                    self.lock.unlock()
                    request.finish(result)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    request.finish(.failure(AudioPreparationError.timedOut))
                }
            }
        } onCancel: {
            request.finish(.failure(CancellationError()))
        }
    }
}

private final class Request<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var finished = false

    func register(_ continuation: CheckedContinuation<Value, Error>) -> Bool {
        lock.lock()
        guard !finished else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
