import XCTest
@testable import AudioWhisper

@MainActor
final class RecordingPresentationTests: IsolatedXCTestCase {
    func testConfiguredShortcutUpdatesMenuAndSpokenHint() {
        let item = NSMenuItem()
        RecordingShortcut.apply("⌥R", to: item)
        XCTAssertEqual(item.keyEquivalent.lowercased(), "r")
        XCTAssertTrue(item.keyEquivalentModifierMask.contains(.option))
        XCTAssertFalse(item.keyEquivalentModifierMask.contains(.command))
        XCTAssertEqual(RecordingShortcut.display("⌥R"), "⌥R")
        XCTAssertEqual(RecordingShortcut.spoken("⌥R"), "Option R")
        RecordingShortcut.apply("invalid", to: item)
        XCTAssertEqual(item.keyEquivalent, "")
    }

    func testSuccessDurationUsesAudioDurationAndOmitsUnknownDuration() {
        XCTAssertEqual(SuccessRecapLabel(duration: 2.4, wordCount: 8).label, "8 words · 2.4s")
        XCTAssertEqual(SuccessRecapLabel(duration: nil, wordCount: nil).label, "Copied")
        XCTAssertEqual(SuccessRecapLabel(duration: .nan, wordCount: 8).label, "8 words")
    }
}
