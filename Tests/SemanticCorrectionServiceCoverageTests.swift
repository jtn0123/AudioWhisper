import XCTest
@testable import AudioWhisper

/// Coverage tests for `CorrectionOutcome` and `SemanticCorrectionService`
/// outcome-aware entry points.
final class SemanticCorrectionServiceCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): correctWithOutcome reads `semanticCorrectionMode` from
    // AppDefaults, which is backed by UserDefaults.standard.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var originalMode: String?

    override func setUp() {
        super.setUp()
        originalMode = UserDefaults.standard.string(forKey: "semanticCorrectionMode")
    }

    override func tearDown() {
        if let originalMode {
            UserDefaults.standard.set(originalMode, forKey: "semanticCorrectionMode")
        } else {
            UserDefaults.standard.removeObject(forKey: "semanticCorrectionMode")
        }
        super.tearDown()
    }

    // MARK: - CorrectionOutcome.text

    func testCorrectionOutcomeAppliedText() {
        let outcome = CorrectionOutcome.applied("corrected")
        XCTAssertEqual(outcome.text, "corrected")
    }

    func testCorrectionOutcomeSkippedText() {
        let outcome = CorrectionOutcome.skipped("original")
        XCTAssertEqual(outcome.text, "original")
    }

    func testCorrectionOutcomeFailedText() {
        let err = NSError(domain: "MLX", code: 7)
        let outcome = CorrectionOutcome.failed(err, fallback: "fallback text")
        XCTAssertEqual(outcome.text, "fallback text")
    }

    // MARK: - correctWithOutcome: off mode

    func testCorrectWithOutcomeOffReturnsSkipped() async {
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        let service = SemanticCorrectionService()
        let outcome = await service.correctWithOutcome(
            text: "raw transcript",
            providerUsed: .parakeet
        )
        if case .skipped(let value) = outcome {
            XCTAssertEqual(value, "raw transcript")
        } else {
            XCTFail("Expected .skipped, got \(outcome)")
        }
    }

    func testCorrectOffReturnsOriginalText() async {
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        let service = SemanticCorrectionService()
        let result = await service.correct(text: "hello world", providerUsed: .local)
        XCTAssertEqual(result, "hello world")
    }

    func testCorrectWithOutcomePassesBundleId() async {
        UserDefaults.standard.set("off", forKey: "semanticCorrectionMode")
        let service = SemanticCorrectionService()
        // With a bundle id the category lookup runs; off-mode still skips.
        let outcome = await service.correctWithOutcome(
            text: "text",
            providerUsed: .local,
            sourceAppBundleId: "com.apple.Notes"
        )
        XCTAssertEqual(outcome.text, "text")
    }

    // MARK: - safeMerge additional edges

    func testSafeMergeRejectsWhitespaceCorrectedAtLowThreshold() {
        // Whitespace-only corrected is non-empty, so the edit-distance check
        // runs; at a low threshold the large change is rejected.
        let result = SemanticCorrectionService.safeMerge(
            original: "keep me",
            corrected: "   \n  ",
            maxChangeRatio: 0.25
        )
        XCTAssertEqual(result, "keep me")
    }

    func testNormalizedEditDistanceLongerFirstArg() {
        let distance = SemanticCorrectionService.normalizedEditDistance(
            a: "hello there",
            b: "hello"
        )
        XCTAssertGreaterThan(distance, 0.0)
        XCTAssertLessThanOrEqual(distance, 1.0)
    }
}
