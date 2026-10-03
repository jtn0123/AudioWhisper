import XCTest
import AppKit
@testable import AudioWhisper

@MainActor
final class PasteManagerTests: IsolatedXCTestCase {
    // Deferred(D1): PasteManager reads `enableSmartPaste` from
    // UserDefaults.standard directly. Once it accepts an injected
    // UserDefaults, route writes through a UUID-scoped suite and re-enable.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    override func setUp() {
        super.setUp()
        // Ensure clean state before each test
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
        NSPasteboard.general.clearContents()
    }

    override func tearDown() {
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeManager(permissionGranted: Bool) -> PasteManager {
        let manager = PasteManager(
            accessibilityManager: AccessibilityPermissionManager(permissionCheck: { permissionGranted })
        )
        return manager
    }

}
