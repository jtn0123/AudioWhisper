import XCTest
@testable import AudioWhisper

final class AccessibilityPermissionManagerTests: XCTestCase {

    private final class Counter { var value = 0 }

    private func makeManager(granted: Bool, counter: Counter) -> AccessibilityPermissionManager {
        AccessibilityPermissionManager {
            counter.value += 1
            return granted
        }
    }

    func testPermissionStatusMessageReflectsPermissionState() {
        let grantedCounter = Counter()
        let grantedManager = makeManager(granted: true, counter: grantedCounter)
        XCTAssertEqual(
            grantedManager.permissionStatusMessage,
            "Accessibility permission granted - SmartPaste is enabled"
        )

        let deniedCounter = Counter()
        let deniedManager = makeManager(granted: false, counter: deniedCounter)
        XCTAssertEqual(
            deniedManager.permissionStatusMessage,
            "Accessibility permission required for SmartPaste functionality"
        )
    }

    func testDetailedPermissionStatusIncludesTroubleshootingWhenDenied() {
        let counter = Counter()
        let manager = makeManager(granted: false, counter: counter)

        let status = manager.detailedPermissionStatus

        XCTAssertFalse(status.isGranted)
        XCTAssertEqual(status.statusMessage, "Accessibility permission is not granted")
        XCTAssertEqual(counter.value, 1)
        XCTAssertNotNil(status.troubleshootingInfo)
        XCTAssertTrue(status.troubleshootingInfo?.contains("System Settings") ?? false)
    }

}
