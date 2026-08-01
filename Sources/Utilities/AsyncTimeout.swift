import Foundation

/// Error thrown when an async operation times out
enum AsyncTimeoutError: Error, LocalizedError {
    case timedOut(TimeInterval)

    var errorDescription: String? {
        switch self {
        case .timedOut(let seconds):
            return "Operation timed out after \(Int(seconds)) seconds"
        }
    }
}

/// Wraps an async operation with a timeout.
/// If the operation doesn't complete within the timeout, throws `AsyncTimeoutError.timedOut`.
///
/// - Parameters:
///   - timeout: Maximum time to wait in seconds
///   - operation: The async operation to perform
/// - Returns: The result of the operation
/// - Throws: `AsyncTimeoutError.timedOut` if timeout expires, or any error from the operation
func withTimeout<T: Sendable>(
    _ timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw AsyncTimeoutError.timedOut(timeout)
        }

        // Wait for the first task to complete
        guard let result = try await group.next() else {
            throw AsyncTimeoutError.timedOut(timeout)
        }

        // Cancel the remaining task (either the timeout or the operation)
        group.cancelAll()
        return result
    }
}

// MARK: - Callback Bridge Utilities

/// A thread-safe wrapper that ensures a callback is only invoked once.
/// Useful when bridging callback-based APIs (like Alamofire) to Swift Concurrency,
/// where the callback might be called multiple times but continuation.resume() must only be called once.
final class OnceCallback<T>: @unchecked Sendable {
    private var hasBeenCalled = false
    private let lock = NSLock()
    private let handler: (Result<T, Error>) -> Void

    init(handler: @escaping (Result<T, Error>) -> Void) {
        self.handler = handler
    }

    /// Invokes the handler if it hasn't been called yet.
    /// Thread-safe: only the first call will execute the handler.
    func callOnce(_ result: Result<T, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasBeenCalled else { return }
        hasBeenCalled = true
        handler(result)
    }

}
