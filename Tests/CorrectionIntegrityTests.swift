import XCTest
@testable import AudioWhisper

final class CorrectionIntegrityTests: XCTestCase {
    func testRejectsLostNegationAndChangedAmounts() {
        for (original, edited) in [
            ("Do not delete the backup.", "Delete the backup."),
            ("I can't approve Thursday.", "I can approve Thursday."),
            ("The balance is negative 125.", "The balance is 125."),
            ("Refund $125 to Jordan.", "Refund $1250 to Jordan."),
            ("Please tell Jordan it is ready.", "Please tell Logan it is ready.")
        ] {
            XCTAssertEqual(merge(original, edited), original)
        }
    }

    func testRejectsObservedInstructionLossAndInventedEmail() {
        let command = "Run `grep -v error app.log | less`. Do not replace -v with -d."
        XCTAssertEqual(merge(command, "Run `grep -v error app.log | less`.", ratio: 0.85), command)
        let relay = "Please let Siobhan know that the refund is $125. No attachment is included."
        XCTAssertEqual(merge(relay, relay + "\n\nBest regards,\n\n[Your Name]"), relay)
        XCTAssertEqual(merge(relay, "Hi Siobhan,\n\nPlease note that the refund amount is $125. "
            + "No attachments are included with this message.\n\nBest regards,"), relay)
    }

    func testPreservesLiteralFlagsAndIdentifiers() {
        for (original, edited) in [
            ("Run grep -v error app.log.", "Run grep -d error app.log."),
            ("Send it to editor@example.com.", "Send it to owner@example.com."),
            ("Open /tmp/report.txt.", "Open /tmp/reports.txt.")
        ] {
            XCTAssertEqual(merge(original, edited, ratio: 0.85), original)
        }
    }

    func testAcceptsHarmlessGrammarAndExistingEmailStructure() {
        for (original, edited) in [
            ("hello how are you doing today", "Hello, how are you doing today?"),
            ("I can't approve Thursday.", "I cannot approve Thursday."),
            ("The balance is negative 125.", "The balance is negative 125."),
            ("Refund $1250.50 to Jordan.", "Refund $1,250.50 to Jordan."),
            ("Hi Siobhan, Tuesday is fine.\nBest regards, Justin",
             "Hi Siobhan,\nTuesday is fine.\nBest regards, Justin")
        ] {
            XCTAssertEqual(merge(original, edited), edited)
        }
    }

    func testLongUnrelatedEditsAreRejectedAtEveryCategoryThreshold() {
        let original = String(repeating: "alpha ", count: 900)
        let edited = String(repeating: "bravo ", count: 900)
        for ratio in [0.6, 0.85] { XCTAssertEqual(merge(original, edited, ratio: ratio), original) }
    }

    func testLongSmallCorrectionSurvivesAndTruncationDoesNot() {
        let original = String(repeating: "The release is ready. ", count: 450)
        let edited = "The release is nearly ready. " + String(original.dropFirst("The release is ready. ".count))
        XCTAssertEqual(merge(original, edited), edited.trimmingCharacters(in: .whitespacesAndNewlines))
        XCTAssertEqual(merge(original, String(original.prefix(original.count / 4))), original)
    }

    func testLargeAdversarialComparisonFailsClosedWithinBudget() {
        let original = String(repeating: "alpha ", count: 20000)
        let edited = String(repeating: "bravo ", count: 20000)
        let start = Date()
        XCTAssertEqual(merge(original, edited), original)
        XCTAssertLessThan(Date().timeIntervalSince(start), 3, "Guard must not run an unbounded quadratic comparison")
    }

    private func merge(_ original: String, _ edited: String, ratio: Double = 0.6) -> String {
        SemanticCorrectionService.safeMerge(original: original, corrected: edited, maxChangeRatio: ratio)
    }
}
