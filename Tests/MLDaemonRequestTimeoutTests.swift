import XCTest

@testable import AudioWhisper

/// A finished request must not leave its deadline task sleeping for the full
/// timeout: one leaked task per dictation adds up over a long session.
final class MLDaemonRequestTimeoutTests: XCTestCase {
    private let manager = MLDaemonManager.shared

    override func setUp() async throws {
        try await super.setUp()
        await manager.resetForTesting()
    }

    override func tearDown() async throws {
        await manager.resetForTesting()
        try await super.tearDown()
    }

    private func sleeper() -> Task<Void, Never> {
        Task { try? await Task.sleep(for: .seconds(60)) }
    }

    func testAReplyCancelsTheDeadline() async {
        let deadline = sleeper()
        await manager.injectPending(id: 3, timeout: deadline) { _ in }
        await manager.handle(line: #"{"jsonrpc":"2.0","id":3,"result":{"pong":true}}"#)
        XCTAssertTrue(deadline.isCancelled)
    }

    func testAnErrorReplyCancelsTheDeadline() async {
        let deadline = sleeper()
        await manager.injectPending(id: 4, timeout: deadline) { _ in }
        await manager.handle(line: #"{"jsonrpc":"2.0","id":4,"error":{"message":"boom"}}"#)
        XCTAssertTrue(deadline.isCancelled)
    }

    func testCancellingTheRequestCancelsTheDeadline() async {
        let deadline = sleeper()
        await manager.injectPending(id: 5, timeout: deadline) { _ in }
        await manager.cancelRequest(5)
        XCTAssertTrue(deadline.isCancelled)
    }

    func testFailingEveryRequestCancelsEveryDeadline() async {
        let first = sleeper(), second = sleeper()
        await manager.injectPending(id: 6, timeout: first) { _ in }
        await manager.injectPending(id: 7, timeout: second) { _ in }
        await manager.completeAllPending(with: MLDaemonError.daemonUnavailable("test"))
        XCTAssertTrue(first.isCancelled && second.isCancelled)
    }
}
