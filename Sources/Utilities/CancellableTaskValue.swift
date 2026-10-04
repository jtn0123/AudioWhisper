import Foundation

/// Releases a canceled caller while a worker retains responsibility for its resources.
func cancellableValue<Value: Sendable>(of task: Task<Value, Error>) async throws -> Value {
    let bridge = TaskValueBridge<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            bridge.install(continuation)
            Task.detached {
                do { bridge.finish(.success(try await task.value)) } catch { bridge.finish(.failure(error)) }
            }
        }
    } onCancel: {
        bridge.finish(.failure(CancellationError()))
    }
}

private final class TaskValueBridge<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var result: Result<Value, Error>?

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let completed: Result<Value, Error>? = lock.withLock {
            if let result { return result }
            self.continuation = continuation
            return nil as Result<Value, Error>?
        }
        if let completed { continuation.resume(with: completed) }
    }

    func finish(_ result: Result<Value, Error>) {
        let waiting = lock.withLock {
            guard self.result == nil else { return nil as CheckedContinuation<Value, Error>? }
            self.result = result
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(with: result)
    }
}
