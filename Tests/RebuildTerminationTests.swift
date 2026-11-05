import XCTest

@testable import AudioWhisper

@MainActor
final class RebuildTerminationTests: XCTestCase {
    func testRepliesAsSoonAsCleanupFinishes() async {
        var replies = 0
        let replied = expectation(description: "reply")
        RebuildTermination.run(deadline: .seconds(30), work: {}, reply: {
            replies += 1
            replied.fulfill()
        })
        await fulfillment(of: [replied], timeout: 2)
        XCTAssertEqual(replies, 1)
    }

    func testWedgedCleanupCannotHoldTheAppOpen() async {
        var replies = 0
        let replied = expectation(description: "reply")
        RebuildTermination.run(
            deadline: .milliseconds(50),
            work: { try? await Task.sleep(for: .seconds(60)) },
            reply: {
                replies += 1
                replied.fulfill()
            })
        await fulfillment(of: [replied], timeout: 2)
        XCTAssertEqual(replies, 1)
    }

    func testRepliesOnlyOnceWhenCleanupFinishesAfterTheDeadline() async {
        var replies = 0
        let done = expectation(description: "work finished")
        RebuildTermination.run(
            deadline: .milliseconds(20),
            work: {
                try? await Task.sleep(for: .milliseconds(150))
                done.fulfill()
            },
            reply: { replies += 1 })
        await fulfillment(of: [done], timeout: 2)
        await Task.yield()
        XCTAssertEqual(replies, 1)
    }
}
