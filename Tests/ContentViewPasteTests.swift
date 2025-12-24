import XCTest
@testable import AudioWhisper

final class ContentViewPasteTests: XCTestCase {

    // MARK: - ResumedFlag Tests (Bug #1 regression prevention)

    func testResumedFlagPreventsDoubleResume() {
        let flag = ResumedFlag()

        // First call should succeed
        XCTAssertTrue(flag.tryResume())

        // Second call should fail
        XCTAssertFalse(flag.tryResume())

        // Subsequent calls should also fail
        XCTAssertFalse(flag.tryResume())
    }

    func testResumedFlagThreadSafety() async {
        let flag = ResumedFlag()
        var resumeCount = 0
        let lock = NSLock()

        await withTaskGroup(of: Bool.self) { group in
            // Launch 100 concurrent tasks trying to resume
            for _ in 0..<100 {
                group.addTask {
                    return flag.tryResume()
                }
            }

            for await result in group {
                if result {
                    lock.lock()
                    resumeCount += 1
                    lock.unlock()
                }
            }
        }

        // Exactly one should succeed
        XCTAssertEqual(resumeCount, 1, "Only one resume should succeed even with concurrent calls")
    }

    func testResumedFlagMultipleInstances() {
        let flag1 = ResumedFlag()
        let flag2 = ResumedFlag()

        // Each instance should track its own state
        XCTAssertTrue(flag1.tryResume())
        XCTAssertTrue(flag2.tryResume())

        // Both should now be exhausted
        XCTAssertFalse(flag1.tryResume())
        XCTAssertFalse(flag2.tryResume())
    }
}
