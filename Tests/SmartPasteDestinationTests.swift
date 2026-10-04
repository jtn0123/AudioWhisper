import XCTest
@testable import AudioWhisper

@MainActor
final class SmartPasteDestinationTests: IsolatedXCTestCase {
    func testForegroundMismatchNeverEmitsPaste() async {
        var events = 0
        let manager = PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { true }),
            foregroundPID: { 222 }, pasteEvent: { events += 1 }
        )
        await manager.pasteWithCompletionHandler(expectedTargetPID: 111)
        XCTAssertEqual(events, 0)
    }

    func testRetiredSessionNeverEmitsPaste() async {
        var events = 0
        let manager = PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { true }),
            foregroundPID: { 111 }, pasteEvent: { events += 1 }
        )
        await manager.pasteWithCompletionHandler(expectedTargetPID: 111, isSessionValid: { false })
        XCTAssertEqual(events, 0)
    }

    func testMatchingDestinationEmitsExactlyOnePaste() async {
        var events = 0
        let manager = PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { true }),
            foregroundPID: { 111 }, pasteEvent: { events += 1 }
        )
        await manager.pasteWithCompletionHandler(expectedTargetPID: 111)
        XCTAssertEqual(events, 1)
    }

    func testCapturedMissingDestinationIgnoresLaterGlobalTarget() {
        let vm = RecordingViewModel()
        vm.hasCapturedPasteTarget = true
        vm.targetAppForPaste = nil
        WindowController.storedTargetApp = NSWorkspace.shared.runningApplications.first
        defer { WindowController.storedTargetApp = nil }
        XCTAssertNil(vm.findValidTargetApp())
    }
}
