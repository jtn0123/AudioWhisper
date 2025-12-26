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

/// Default timeout for network transcription requests (60 seconds)
let transcriptionNetworkTimeout: TimeInterval = 60

/// Default timeout for semantic correction requests (30 seconds)
let semanticCorrectionTimeout: TimeInterval = 30
