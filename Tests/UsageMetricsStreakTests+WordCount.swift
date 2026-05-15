import XCTest
@testable import AudioWhisper

// Word count estimation tests, split out of UsageMetricsStreakTests to keep
// each file/type within SwiftLint's body-length limits.
@MainActor
extension UsageMetricsStreakTests {
    func testWordCountWithEmptyString() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: ""), 0)
    }

    func testWordCountWithSingleWord() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello"), 1)
    }

    func testWordCountWithContractions() {
        // Contractions should count as single words
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "don't won't can't"), 3)
    }

    func testWordCountWithNumbers() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "I have 42 apples"), 4)
    }

    func testWordCountWithPunctuation() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "Hello, world! How are you?"), 5)
    }

    func testWordCountWithMultipleSpaces() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello    world"), 2)
    }

    func testWordCountWithNewlines() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello\nworld"), 2)
    }

    func testWordCountWithTabs() {
        XCTAssertEqual(UsageMetricsStore.estimatedWordCount(for: "hello\tworld"), 2)
    }
}
