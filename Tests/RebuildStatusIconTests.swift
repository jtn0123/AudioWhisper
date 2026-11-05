import XCTest

@testable import AudioWhisper

final class RebuildStatusIconTests: XCTestCase {
    func testIdleShowsTheAppIcon() {
        XCTAssertEqual(RebuildStatusIcon.resolve(phase: .idle, meeting: .idle, failureVisible: false), .idle)
        XCTAssertEqual(RebuildStatusIcon.resolve(phase: .completed, meeting: .idle, failureVisible: false), .idle)
    }

    func testRecordingIsAlwaysVisibleAndAnnounced() {
        let dictation = RebuildStatusIcon.resolve(phase: .recording, meeting: .idle, failureVisible: false)
        let meeting = RebuildStatusIcon.resolve(phase: .idle, meeting: .capturing, failureVisible: false)
        for icon in [dictation, meeting] {
            XCTAssertTrue(icon.isAlert)
            XCTAssertEqual(icon.symbol, "record.circle.fill")
            XCTAssertTrue(icon.label.contains("recording"))
        }
    }

    func testRecordingOutranksEveryOtherState() {
        let icon = RebuildStatusIcon.resolve(phase: .transcribing, meeting: .capturing, failureVisible: false)
        XCTAssertTrue(icon.isAlert)
    }

    func testStartingAndTranscribingHaveTheirOwnIcons() {
        let starting = RebuildStatusIcon.resolve(phase: .starting, meeting: .idle, failureVisible: false)
        let working = RebuildStatusIcon.resolve(phase: .transcribing, meeting: .idle, failureVisible: false)
        let meeting = RebuildStatusIcon.resolve(phase: .idle, meeting: .processing, failureVisible: false)
        XCTAssertEqual(starting.symbol, "mic.circle")
        XCTAssertEqual(working.symbol, "ellipsis.circle")
        XCTAssertEqual(meeting, working)
        XCTAssertFalse(starting.isAlert || working.isAlert)
    }

    func testFailureShowsOnlyWhileTheRecorderExplainsIt() {
        let shown = RebuildStatusIcon.resolve(phase: .failed, meeting: .idle, failureVisible: true)
        let settled = RebuildStatusIcon.resolve(phase: .failed, meeting: .idle, failureVisible: false)
        XCTAssertEqual(shown.symbol, "exclamationmark.circle")
        XCTAssertEqual(settled, .idle)
    }

    func testEverySymbolExists() {
        let icons: [RebuildStatusIcon] = [
            .idle,
            .resolve(phase: .recording, meeting: .idle, failureVisible: false),
            .resolve(phase: .starting, meeting: .idle, failureVisible: false),
            .resolve(phase: .transcribing, meeting: .idle, failureVisible: false),
            .resolve(phase: .failed, meeting: .idle, failureVisible: true)
        ]
        for icon in icons {
            XCTAssertNotNil(NSImage(systemSymbolName: icon.symbol, accessibilityDescription: nil), icon.symbol)
        }
    }
}
