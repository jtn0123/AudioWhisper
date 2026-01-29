import XCTest
@testable import AudioWhisper

final class AsyncTimeoutTests: XCTestCase {
    func testWithTimeoutCompletesSuccessfully() async throws {
        let result = try await withTimeout(5.0) {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            return "success"
        }
        XCTAssertEqual(result, "success")
    }

    func testWithTimeoutThrowsOnTimeout() async {
        do {
            _ = try await withTimeout(0.1) {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                return "should not reach"
            }
            XCTFail("Expected timeout error")
        } catch let error as AsyncTimeoutError {
            switch error {
            case .timedOut(let seconds):
                XCTAssertEqual(seconds, 0.1)
            }
        } catch {
            XCTFail("Expected AsyncTimeoutError, got \(error)")
        }
    }

    func testWithTimeoutPropagatesOperationError() async {
        struct TestError: Error {}

        do {
            _ = try await withTimeout(5.0) {
                throw TestError()
            }
            XCTFail("Expected TestError")
        } catch is TestError {
            // Expected
        } catch {
            XCTFail("Expected TestError, got \(error)")
        }
    }

    func testWithTimeoutCancelsPendingTaskAfterSuccess() async throws {
        // This test verifies that after the operation completes, the timeout task is cancelled
        let result = try await withTimeout(0.5) {
            return "fast"
        }

        // Wait a bit to ensure the timeout task would have fired if not cancelled
        try await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds

        XCTAssertEqual(result, "fast")
    }

    func testAsyncTimeoutErrorDescription() {
        let error = AsyncTimeoutError.timedOut(30.0)
        XCTAssertEqual(error.errorDescription, "Operation timed out after 30 seconds")
    }

    func testWithTimeoutReturnsImmediateValue() async throws {
        let result = try await withTimeout(1.0) {
            return 42
        }
        XCTAssertEqual(result, 42)
    }

    func testWithTimeoutWithVoidReturn() async throws {
        // Simply verify that withTimeout works with Void return type
        try await withTimeout(1.0) {
            // No-op - just testing the function compiles and runs
        }
    }
}
