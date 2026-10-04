import XCTest
@testable import AudioWhisper

final class AudioHardwarePreparationTests: XCTestCase {
    func testBlockedHardwareTimesOutWithoutBlockingMainOrQueueingAnotherStart() async {
        let preparation = AudioHardwarePreparation<Int>()
        let entered = expectation(description: "Hardware entered")
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            try await preparation.run(timeout: 0.05) {
                XCTAssertFalse(Thread.isMainThread)
                entered.fulfill()
                release.wait()
                return 42
            }
        }
        await fulfillment(of: [entered], timeout: 1)
        await MainActor.run { XCTAssertTrue(Thread.isMainThread) }
        do { _ = try await task.value; XCTFail("Blocked input must time out") } catch {
            XCTAssertTrue(error is AudioPreparationError)
        }
        do {
            _ = try await preparation.run { XCTFail("Must not queue another hardware call"); return 99 }
            XCTFail("Stalled worker must remain busy")
        } catch { XCTAssertTrue(error is AudioPreparationError) }
        release.signal()
        for _ in 0..<100 where preparation.isInFlight { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(preparation.isInFlight)
        do { let value = try await preparation.run { 77 }; XCTAssertEqual(value, 77) } catch { XCTFail("\(error)") }
    }

    func testCancelledPreparationCannotDeliverALateReadyInput() async {
        let preparation = AudioHardwarePreparation<Int>()
        let entered = expectation(description: "Hardware entered")
        let release = DispatchSemaphore(value: 0)
        let task = Task {
            try await preparation.run {
                entered.fulfill()
                release.wait()
                return 42
            }
        }
        await fulfillment(of: [entered], timeout: 1)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled input must not become ready") } catch {
            XCTAssertTrue(error is CancellationError)
        }
        release.signal()
        for _ in 0..<100 where preparation.isInFlight { try? await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertFalse(preparation.isInFlight)
    }
}
