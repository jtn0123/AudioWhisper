import XCTest
import AppKit
@testable import AudioWhisper

// MARK: - AppSetupHelper Tests
@MainActor
final class AppSetupHelperCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): checkFirstRun reads/writes AppDefaults (UserDefaults.standard).
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private var originalProvider: Any?
    private var originalCompletedWelcome: Any?
    private var originalWelcomeVersion: Any?
    private var originalIconSize: Any?

    override func setUp() {
        super.setUp()
        originalProvider = UserDefaults.standard.object(forKey: AppDefaults.Key.transcriptionProvider.rawValue)
        originalCompletedWelcome = UserDefaults.standard.object(forKey: AppDefaults.Key.hasCompletedWelcome.rawValue)
        originalWelcomeVersion = UserDefaults.standard.object(forKey: AppDefaults.Key.lastWelcomeVersion.rawValue)
        originalIconSize = UserDefaults.standard.object(forKey: AppDefaults.Key.menuBarIconSize.rawValue)
    }

    override func tearDown() {
        restore(originalProvider, AppDefaults.Key.transcriptionProvider)
        restore(originalCompletedWelcome, AppDefaults.Key.hasCompletedWelcome)
        restore(originalWelcomeVersion, AppDefaults.Key.lastWelcomeVersion)
        restore(originalIconSize, AppDefaults.Key.menuBarIconSize)
        AppSetupHelper.resetIconSizeCache()
        super.tearDown()
    }

    private func restore(_ value: Any?, _ key: AppDefaults.Key) {
        if let value = value {
            UserDefaults.standard.set(value, forKey: key.rawValue)
        } else {
            UserDefaults.standard.removeObject(forKey: key.rawValue)
        }
    }

    // MARK: - createMenuBarIcon

    func testCreateMenuBarIconReturnsTemplateImage() {
        let icon = AppSetupHelper.createMenuBarIcon()
        XCTAssertNotNil(icon)
        XCTAssertTrue(icon.isTemplate)
    }

    // MARK: - Icon Size

    func testAdaptiveIconSizeWithUserOverride() {
        AppDefaults.menuBarIconSize = 19.0
        AppSetupHelper.resetIconSizeCache()
        XCTAssertEqual(AppSetupHelper.getAdaptiveMenuBarIconSize(), 19.0)
    }

    func testAdaptiveIconSizeIgnoresZeroOverride() {
        AppDefaults.menuBarIconSize = 0.0
        AppSetupHelper.resetIconSizeCache()
        // Zero override is rejected; falls back to a positive computed size.
        XCTAssertGreaterThan(AppSetupHelper.getAdaptiveMenuBarIconSize(), 0)
    }

    func testAdaptiveIconSizeWithoutOverrideIsPositive() {
        AppDefaults.menuBarIconSize = nil
        AppSetupHelper.resetIconSizeCache()
        XCTAssertGreaterThan(AppSetupHelper.getAdaptiveMenuBarIconSize(), 0)
    }

    func testAdaptiveIconSizeIsCachedOnSecondCall() {
        AppDefaults.menuBarIconSize = nil
        AppSetupHelper.resetIconSizeCache()
        let first = AppSetupHelper.getAdaptiveMenuBarIconSize()
        let second = AppSetupHelper.getAdaptiveMenuBarIconSize()
        XCTAssertEqual(first, second)
    }

    func testResetIconSizeCacheDoesNotCrash() {
        AppSetupHelper.resetIconSizeCache()
        AppSetupHelper.resetIconSizeCache()
    }

    // MARK: - checkFirstRun

    func testCheckFirstRunForBrandNewUserDefaultsToLocalProvider() {
        AppDefaults.removeValue(for: .transcriptionProvider)
        AppDefaults.removeValue(for: .hasCompletedWelcome)
        AppDefaults.removeValue(for: .lastWelcomeVersion)

        let shouldShowWelcome = AppSetupHelper.checkFirstRun()

        XCTAssertTrue(shouldShowWelcome)
        XCTAssertEqual(AppDefaults.transcriptionProvider, .local)
    }

    func testCheckFirstRunWhenWelcomeAlreadyCurrentReturnsFalse() {
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.hasCompletedWelcome = true
        AppDefaults.lastWelcomeVersion = "1.1"

        let shouldShowWelcome = AppSetupHelper.checkFirstRun()

        XCTAssertFalse(shouldShowWelcome)
        XCTAssertEqual(AppDefaults.transcriptionProvider, .parakeet)
    }

    func testCheckFirstRunForExistingUserOnOldWelcomeVersion() {
        AppDefaults.transcriptionProvider = .parakeet
        AppDefaults.hasCompletedWelcome = true
        AppDefaults.lastWelcomeVersion = "1.0"

        let shouldShowWelcome = AppSetupHelper.checkFirstRun()

        XCTAssertTrue(shouldShowWelcome)
    }

    // MARK: - File Helpers

    func testEnsurePromptFilesDoesNotCrash() {
        AppSetupHelper.ensurePromptFiles()
    }

    func testCleanupOldTemporaryFilesDoesNotCrash() {
        AppSetupHelper.cleanupOldTemporaryFiles()
    }

    func testSetupLoginItemDoesNotCrash() {
        AppSetupHelper.setupLoginItem()
    }
}
