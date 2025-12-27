import XCTest
@testable import AudioWhisper

final class ContentViewPasteTests: XCTestCase {

    // MARK: - ResumedFlag Tests (bug regression prevention)

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
        // Use actor for thread-safe counting in async context
        actor Counter {
            var value = 0
            func increment() { value += 1 }
            func get() -> Int { value }
        }
        let counter = Counter()

        await withTaskGroup(of: Bool.self) { group in
            // Launch 100 concurrent tasks trying to resume
            for _ in 0..<100 {
                group.addTask {
                    return flag.tryResume()
                }
            }

            for await result in group {
                if result {
                    await counter.increment()
                }
            }
        }

        // Exactly one should succeed
        let finalCount = await counter.get()
        XCTAssertEqual(finalCount, 1, "Only one resume should succeed even with concurrent calls")
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
