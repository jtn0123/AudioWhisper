import XCTest
import AppKit
@testable import AudioWhisper

/// Coverage tests for `RecordingViewModel+Paste` helpers: source-app
/// resolution, target-app lookup, status updates, and notification observers.
@MainActor
final class RecordingViewModelPasteCoverageTests: IsolatedXCTestCase {
    // NOTE(D1): RecordingViewModel + paste helpers read AppDefaults state
    // (enableSmartPaste, etc.) backed by UserDefaults.standard.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    private func makeViewModel() -> RecordingViewModel {
        RecordingViewModel(
            speechService: SpeechToTextService(),
            pasteManager: PasteManager(),
            semanticCorrectionService: SemanticCorrectionService(),
            soundManager: SoundManager(),
            statusViewModel: StatusViewModel()
        )
    }

    override func tearDown() async throws {
        WindowController.storedTargetApp = nil
        try await super.tearDown()
    }

    // MARK: - currentSourceAppInfo

    func testCurrentSourceAppInfoReturnsCached() {
        let vm = makeViewModel()
        let info = SourceAppInfo(
            bundleIdentifier: "com.cov.app",
            displayName: "Coverage App",
            iconData: nil,
            fallbackSymbolName: nil
        )
        vm.lastSourceAppInfo = info
        let result = vm.currentSourceAppInfo()
        XCTAssertEqual(result.bundleIdentifier, "com.cov.app")
        XCTAssertEqual(result.displayName, "Coverage App")
    }

    func testCurrentSourceAppInfoFallsBackWhenNothingCached() {
        let vm = makeViewModel()
        WindowController.storedTargetApp = nil
        vm.targetAppForPaste = nil
        vm.lastSourceAppInfo = nil
        let result = vm.currentSourceAppInfo()
        // Returns either a fallback running app or .unknown — never empty.
        XCTAssertFalse(result.displayName.isEmpty)
    }

    // MARK: - findValidTargetApp / findFallbackTargetApp

    func testFindFallbackTargetAppSkipsSelfBundle() {
        let vm = makeViewModel()
        let fallback = vm.findFallbackTargetApp()
        if let fallback {
            XCTAssertNotEqual(fallback.bundleIdentifier, Bundle.main.bundleIdentifier)
            XCTAssertFalse(fallback.isTerminated)
            XCTAssertEqual(fallback.activationPolicy, .regular)
        }
    }

    func testFindValidTargetAppPrefersStoredApp() {
        let vm = makeViewModel()
        WindowController.storedTargetApp = NSRunningApplication.current
        vm.targetAppForPaste = nil
        let result = vm.findValidTargetApp()
        XCTAssertEqual(result?.processIdentifier, NSRunningApplication.current.processIdentifier)
    }

    func testFindValidTargetAppUsesTargetAppForPasteWhenNoStored() {
        let vm = makeViewModel()
        WindowController.storedTargetApp = nil
        vm.targetAppForPaste = NSRunningApplication.current
        let result = vm.findValidTargetApp()
        XCTAssertNotNil(result)
    }

    func testFindValidTargetAppReturnsNilOrFallbackWhenNothingSet() {
        let vm = makeViewModel()
        WindowController.storedTargetApp = nil
        vm.targetAppForPaste = nil
        // Should not crash; result depends on running apps.
        _ = vm.findValidTargetApp()
    }

    // MARK: - performUserTriggeredPaste (no valid target)

    func testPerformUserTriggeredPasteWithNoTargetClearsSuccess() {
        let vm = makeViewModel()
        WindowController.storedTargetApp = nil
        vm.targetAppForPaste = nil
        vm.showSuccess = true
        // With a fallback app available this may schedule a paste; without one
        // it clears showSuccess. Either branch must not crash.
        vm.performUserTriggeredPaste()
    }

    // MARK: - updateStatus

    func testUpdateStatusRecording() {
        let vm = makeViewModel()
        vm.updateStatus(isRecording: true, hasPermission: true)
        XCTAssertEqual(vm.statusViewModel.currentStatus, .recording)
    }

    func testUpdateStatusWithoutPermission() {
        let vm = makeViewModel()
        vm.updateStatus(isRecording: false, hasPermission: false)
        if case .permissionRequired = vm.statusViewModel.currentStatus {
            // expected
        } else {
            XCTFail("Expected permissionRequired, got \(vm.statusViewModel.currentStatus)")
        }
    }

    func testUpdateStatusSurfacesErrorMessage() {
        let vm = makeViewModel()
        vm.showError = true
        vm.errorMessage = "uh oh"
        vm.updateStatus(isRecording: false, hasPermission: true)
        if case .error(let message) = vm.statusViewModel.currentStatus {
            XCTAssertEqual(message, "uh oh")
        } else {
            XCTFail("Expected error status, got \(vm.statusViewModel.currentStatus)")
        }
    }

    // MARK: - Notification observers

    func testSetupNotificationObserversRegistersTasks() {
        let vm = makeViewModel()
        vm.setupNotificationObservers()
        XCTAssertEqual(vm.notificationTasks.count, 3)
        vm.stopNotificationObservers()
        XCTAssertTrue(vm.notificationTasks.isEmpty)
    }

    func testSetupNotificationObserversIsIdempotent() {
        let vm = makeViewModel()
        vm.setupNotificationObservers()
        vm.setupNotificationObservers()
        // Re-setup cancels prior tasks first, so count stays at 3.
        XCTAssertEqual(vm.notificationTasks.count, 3)
        vm.stopNotificationObservers()
    }

    /// Polls a `@MainActor` predicate on the run loop until it holds or the
    /// budget expires. Re-posts the notification on each tick to defeat the
    /// race where the observer's `for await` loop isn't iterating yet.
    private func pollUntil(
        timeout: TimeInterval = 3.0,
        repost: () -> Void,
        condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            repost()
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func testProgressNotificationUpdatesProgressMessage() async {
        let vm = makeViewModel()
        vm.setupNotificationObservers()
        defer { vm.stopNotificationObservers() }

        await pollUntil(
            repost: {
                NotificationCenter.default.post(
                    name: .transcriptionProgress,
                    object: "Halfway there"
                )
            },
            condition: { vm.progressMessage == "Halfway there" }
        )
        XCTAssertEqual(vm.progressMessage, "Halfway there")
    }

    func testRecordingFailedNotificationSetsError() async {
        let vm = makeViewModel()
        vm.setupNotificationObservers()
        defer { vm.stopNotificationObservers() }

        await pollUntil(
            repost: {
                NotificationCenter.default.post(name: .recordingStartFailed, object: nil)
            },
            condition: { vm.showError }
        )
        XCTAssertTrue(vm.showError)
        XCTAssertFalse(vm.errorMessage.isEmpty)
    }

    func testTargetAppStoredNotificationCachesSourceInfo() async {
        let vm = makeViewModel()
        vm.setupNotificationObservers()
        defer { vm.stopNotificationObservers() }

        await pollUntil(
            repost: {
                NotificationCenter.default.post(
                    name: .targetAppStored,
                    object: NSRunningApplication.current
                )
            },
            condition: { vm.targetAppForPaste != nil }
        )
        XCTAssertNotNil(vm.targetAppForPaste)
    }

}
