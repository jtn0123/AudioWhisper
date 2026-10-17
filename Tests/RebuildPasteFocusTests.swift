import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildPasteFocusTests: IsolatedXCTestCase {
    func testDifferentControlsWithTheSameHashNeverTriggerAFallbackPaste() async {
        let first = CollidingControl()
        let second = CollidingControl()
        XCTAssertEqual(CFHash(first), CFHash(second))
        XCTAssertFalse(CFEqual(first, second))
        XCTAssertEqual(FocusedTextControlIdentity(first), FocusedTextControlIdentity(first))
        XCTAssertEqual(FocusedTextControlIdentity(NSNumber(value: 7)), FocusedTextControlIdentity(NSNumber(value: 7)))
        var events = 0
        var menus = 0
        let access = FocusedTextAccess(read: { _ in
            FocusedTextState(length: 0, selection: NSRange(location: 0, length: 0), preceding: "",
                             controlIdentity: .init(events == 0 ? first : second))
        }, pressPasteMenuItem: { _ in menus += 1; return true })
        let delivery = RebuildPasteDelivery(focusedText: access, confirmationWindow: .milliseconds(5),
                                           pollInterval: .milliseconds(1))
        let outcome = await deliver(delivery, event: { events += 1 })
        XCTAssertEqual(outcome, .unverified)
        XCTAssertEqual(menus, 0)
    }

    func testChangedFieldNeverTriggersAFallbackPaste() async {
        var events = 0
        var menus = 0
        let access = FocusedTextAccess(read: { _ in
            FocusedTextState(length: 0, selection: NSRange(location: 0, length: 0), preceding: "",
                             controlIdentity: .init(NSNumber(value: events == 0 ? 1 : 2)))
        }, pressPasteMenuItem: { _ in menus += 1; return true })
        let delivery = RebuildPasteDelivery(focusedText: access, confirmationWindow: .milliseconds(5),
                                           pollInterval: .milliseconds(1))
        let outcome = await deliver(delivery, event: { events += 1 })
        XCTAssertEqual(outcome, .unverified)
        XCTAssertEqual(events, 1)
        XCTAssertEqual(menus, 0)
    }

    func testChangedForegroundNeverTriggersAFallbackPaste() async {
        var foreground: pid_t? = 111
        var menus = 0
        let access = FocusedTextAccess(read: { _ in
            FocusedTextState(length: 0, selection: NSRange(location: 0, length: 0), preceding: "")
        }, pressPasteMenuItem: { _ in menus += 1; return true })
        let delivery = RebuildPasteDelivery(focusedText: access, confirmationWindow: .milliseconds(5),
                                           pollInterval: .milliseconds(1))
        let outcome = await deliver(delivery, foreground: { foreground }, event: { foreground = 222 })
        XCTAssertEqual(outcome, .cancelled)
        XCTAssertEqual(menus, 0)
    }

    private func deliver(
        _ delivery: RebuildPasteDelivery, foreground: @escaping () -> pid_t? = { 111 }, event: @escaping () -> Void
    ) async -> RebuildPasteDelivery.Outcome {
        let paste = PasteManager(accessibilityManager: AccessibilityPermissionManager(permissionCheck: { true }),
                                 foregroundPID: foreground, pasteEvent: event)
        let target = RebuildPasteDestination(processIdentifier: 111, bundleIdentifier: "fixture.editor",
            activate: { true }, isTerminated: { false }, foregroundPID: foreground)
        return await delivery.deliver("Words", to: target, paste: paste, copy: { _ in }, isValid: { true })
    }
}

private final class CollidingControl: NSObject {
    override var hash: Int { 1 }
}
