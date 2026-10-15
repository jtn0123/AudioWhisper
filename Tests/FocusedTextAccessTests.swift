import XCTest
@testable import AudioWhisper

/// The decisions behind paste confirmation, apart from the live Accessibility
/// calls, and the guard that keeps those calls out of test runs.
@MainActor
final class FocusedTextAccessTests: XCTestCase {
    func testLiveAccessNeverTouchesAccessibilityUnderTests() {
        let live = FocusedTextAccess.live
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertNil(live.read(pid))
        XCTAssertNil(live.watchChanges(pid))
        XCTAssertFalse(live.pressPasteMenuItem(pid))
    }

    func testAccessWithoutAWatcherReportsNoChanges() {
        let access = FocusedTextAccess(read: { _ in nil }, pressPasteMenuItem: { _ in false })
        XCTAssertNil(access.watchChanges(1))
    }

    func testStateMeasuresUTF16AndReadsBeforeTheSelection() {
        var asked: [Int] = []
        let caret = NSRange(location: 5, length: 0)
        let state = FocusedTextAX.state(value: "hi 👋 there", count: nil, selection: caret) {
            asked.append($0)
            return "hi 👋"
        }
        XCTAssertEqual(state, FocusedTextState(length: 11, selection: caret, preceding: "hi 👋"))
        XCTAssertEqual(asked, [5])
    }

    func testReportedCountWinsOverTheValue() {
        let state = FocusedTextAX.state(value: "abc", count: 10, selection: nil) { _ in
            XCTFail("with no selection there is nothing to read before")
            return nil
        }
        XCTAssertEqual(state, FocusedTextState(length: 10, selection: nil, preceding: nil))
    }

    func testControlThatReportsNothingIsUnreadable() {
        XCTAssertNil(FocusedTextAX.state(value: nil, count: nil, selection: nil) { _ in "x" })
    }

    func testTextBeforeTheCaret() {
        XCTAssertEqual(FocusedTextAX.text("Hello world", before: 5), "Hello")
        XCTAssertEqual(FocusedTextAX.text("Hello", before: 0), "", "the start of the field has empty context")
        XCTAssertNil(FocusedTextAX.text(nil, before: 3))
        XCTAssertNil(FocusedTextAX.text("Hi", before: 9), "a caret past the end is not trusted")
    }

    func testContextWindowKeepsOnlyTheNearestText() {
        let value = String(repeating: "x", count: 10) + String(repeating: "a", count: FocusedTextAX.contextLength)
        XCTAssertEqual(
            FocusedTextAX.text(value, before: (value as NSString).length),
            String(repeating: "a", count: FocusedTextAX.contextLength))
    }

    func testContextWindowNeverStartsInsideAnEmoji() {
        // The emoji is two UTF-16 units, so a 64-unit window ending at the
        // caret would start on its second half.
        let value = "👋" + String(repeating: "a", count: FocusedTextAX.contextLength - 1)
        XCTAssertEqual(FocusedTextAX.text(value, before: (value as NSString).length), value)
    }

    func testOnlyAnEnabledPlainCommandVIsThePasteItem() {
        XCTAssertTrue(FocusedTextAX.isPlainPaste(commandCharacter: "V", modifiers: 0, enabled: true))
        XCTAssertTrue(FocusedTextAX.isPlainPaste(commandCharacter: "v", modifiers: 0, enabled: true))
        XCTAssertFalse(
            FocusedTextAX.isPlainPaste(commandCharacter: "V", modifiers: 3, enabled: true),
            "Paste and Match Style is ⌥⇧⌘V")
        XCTAssertFalse(FocusedTextAX.isPlainPaste(commandCharacter: "V", modifiers: 0, enabled: false))
        XCTAssertFalse(FocusedTextAX.isPlainPaste(commandCharacter: "V", modifiers: 0, enabled: nil))
        XCTAssertFalse(FocusedTextAX.isPlainPaste(commandCharacter: "C", modifiers: 0, enabled: true))
        XCTAssertFalse(FocusedTextAX.isPlainPaste(commandCharacter: nil, modifiers: 0, enabled: true))
    }

    func testOtherMenuItemsCostOneLookup() {
        var lookups = 0
        func counted<T>(_ value: T) -> T {
            lookups += 1
            return value
        }
        XCTAssertFalse(FocusedTextAX.isPlainPaste(
            commandCharacter: "C", modifiers: counted(0), enabled: counted(true)))
        XCTAssertEqual(lookups, 0, "modifiers and enabled state are only read for a V item")
    }
}
