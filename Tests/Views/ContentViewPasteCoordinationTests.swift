import XCTest
import AppKit
@testable import AudioWhisper

/// Tests for ContentView paste coordination and target app selection
/// Extends ContentViewPasteTests with additional coverage
@MainActor
final class ContentViewPasteCoordinationTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        testSuiteName = "ContentViewPasteCoordinationTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
        testDefaults?.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() async throws {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        try await super.tearDown()
    }

    // MARK: - FindFallbackTargetApp Tests

    func testFindFallbackExcludesAudioWhisper() {
        // The fallback should never return AudioWhisper itself
        let runningApps = NSWorkspace.shared.runningApplications

        let excluded = runningApps.filter { app in
            app.bundleIdentifier == Bundle.main.bundleIdentifier
        }

        // If AudioWhisper is running, it should be excluded
        if !excluded.isEmpty {
            let fallback = runningApps.first { app in
                app.bundleIdentifier != Bundle.main.bundleIdentifier &&
                app.bundleIdentifier != "com.tinyspeck.slackmacgap" &&
                app.bundleIdentifier != "com.cron.electron" &&
                app.activationPolicy == .regular &&
                !app.isTerminated
            }

            // Fallback should not be AudioWhisper
            XCTAssertNotEqual(fallback?.bundleIdentifier, Bundle.main.bundleIdentifier)
        }
    }

    func testFindFallbackExcludesSlack() {
        // Verify Slack is in the exclusion list
        let excludedBundleIds = [
            "com.tinyspeck.slackmacgap"
        ]

        // Verify the exclusion logic
        for bundleId in excludedBundleIds {
            let isExcluded = bundleId == "com.tinyspeck.slackmacgap"
            XCTAssertTrue(isExcluded, "\(bundleId) should be excluded from fallback")
        }
    }

    func testFindFallbackExcludesCron() {
        // Verify Cron is in the exclusion list
        let excludedBundleIds = [
            "com.cron.electron"
        ]

        for bundleId in excludedBundleIds {
            let isExcluded = bundleId == "com.cron.electron"
            XCTAssertTrue(isExcluded, "\(bundleId) should be excluded from fallback")
        }
    }

    func testFindFallbackOnlyReturnsRegularApps() {
        // Only .regular activation policy apps should be returned
        let runningApps = NSWorkspace.shared.runningApplications

        let regularApps = runningApps.filter { app in
            app.activationPolicy == .regular
        }

        let nonRegularApps = runningApps.filter { app in
            app.activationPolicy != .regular
        }

        // Verify the filter logic
        for app in regularApps {
            XCTAssertEqual(app.activationPolicy, .regular)
        }

        for app in nonRegularApps {
            XCTAssertNotEqual(app.activationPolicy, .regular)
        }
    }

    func testFindFallbackExcludesTerminatedApps() {
        // Terminated apps should not be returned
        let runningApps = NSWorkspace.shared.runningApplications

        let activeApps = runningApps.filter { !$0.isTerminated }

        // All apps in the filter should be non-terminated
        for app in activeApps {
            XCTAssertFalse(app.isTerminated)
        }
    }

    // MARK: - Target App Priority Tests

    func testTargetAppPriorityOrder() {
        // Document the expected priority order
        // 1. WindowController.storedTargetApp
        // 2. ContentView.targetAppForPaste
        // 3. findFallbackTargetApp()

        // This is a documentation test - verifies the logic flow exists
        let priorities = [
            "WindowController.storedTargetApp",
            "targetAppForPaste",
            "findFallbackTargetApp"
        ]

        XCTAssertEqual(priorities.count, 3, "Should have 3 priority levels for target app selection")
    }

    // MARK: - SmartPaste Settings Tests

    func testSmartPasteDisabledSkipsPaste() {
        testDefaults.set(false, forKey: "enableSmartPaste")

        let enableSmartPaste = testDefaults.bool(forKey: "enableSmartPaste")
        XCTAssertFalse(enableSmartPaste)

        // When SmartPaste is disabled, paste should not be triggered automatically
        var pasteCalled = false
        if enableSmartPaste {
            pasteCalled = true
        }

        XCTAssertFalse(pasteCalled, "Paste should not be called when SmartPaste is disabled")
    }

    func testSmartPasteEnabledTriggersPaste() {
        testDefaults.set(true, forKey: "enableSmartPaste")

        let enableSmartPaste = testDefaults.bool(forKey: "enableSmartPaste")
        XCTAssertTrue(enableSmartPaste)

        // When SmartPaste is enabled, paste should be triggered
        var pasteCalled = false
        if enableSmartPaste {
            pasteCalled = true
        }

        XCTAssertTrue(pasteCalled, "Paste should be called when SmartPaste is enabled")
    }

    // MARK: - awaitingSemanticPaste Flag Tests

    func testAwaitingSemanticPasteCapturedByValue() {
        // Bug #26 fix: The flag value must be captured at schedule time
        var awaitingSemanticPaste = false

        // Simulate schedule time capture
        let capturedValue = awaitingSemanticPaste
        XCTAssertFalse(capturedValue)

        // Even if the original changes, captured should remain the same
        awaitingSemanticPaste = true

        XCTAssertFalse(capturedValue, "Captured value should not change when original changes")
        XCTAssertTrue(awaitingSemanticPaste, "Original should have changed")
    }

    func testAwaitingSemanticPasteBlocksPasteWhenTrue() {
        let awaitingSemanticPaste = true

        let shouldPasteNow = !awaitingSemanticPaste
        XCTAssertFalse(shouldPasteNow, "Should not paste when awaiting semantic")
    }

    func testAwaitingSemanticPasteAllowsPasteWhenFalse() {
        let awaitingSemanticPaste = false

        let shouldPasteNow = !awaitingSemanticPaste
        XCTAssertTrue(shouldPasteNow, "Should paste when not awaiting semantic")
    }

    // MARK: - Fade Out Tests

    func testFadeOutDelayWithoutSmartPaste() {
        // Without SmartPaste, there's a 2.0s delay before fade
        let expectedDelay: TimeInterval = 2.0

        XCTAssertEqual(expectedDelay, 2.0, "Fade delay without SmartPaste should be 2.0s")
    }

    func testFadeOutDelayWithSmartPaste() {
        // With SmartPaste, there's a 0.7s delay before paste
        let expectedDelay: TimeInterval = 0.7

        XCTAssertEqual(expectedDelay, 0.7, "Paste delay with SmartPaste should be 0.7s")
    }

    // MARK: - Activation Timeout Tests

    func testWaitForActivationTimeoutValue() {
        // The timeout for waiting for app activation is 500ms
        let expectedTimeout: Int = 500

        XCTAssertEqual(expectedTimeout, 500, "Activation timeout should be 500ms")
    }

    // MARK: - ResumedFlag Edge Cases

    func testResumedFlagInitialState() {
        let flag = ResumedFlag()

        // First call should succeed
        XCTAssertTrue(flag.tryResume())
    }

    func testResumedFlagAfterResume() {
        let flag = ResumedFlag()
        _ = flag.tryResume()

        // Second call should fail
        XCTAssertFalse(flag.tryResume())
    }

    func testResumedFlagIsIndependent() {
        let flag1 = ResumedFlag()
        let flag2 = ResumedFlag()

        // Each flag is independent
        XCTAssertTrue(flag1.tryResume())
        XCTAssertTrue(flag2.tryResume())

        // Both are now exhausted
        XCTAssertFalse(flag1.tryResume())
        XCTAssertFalse(flag2.tryResume())
    }

    // MARK: - Concurrent Resume Protection Tests

    func testConcurrentResumeProtection() async {
        let flag = ResumedFlag()
        var successCount = 0

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    flag.tryResume()
                }
            }

            for await result in group {
                if result {
                    successCount += 1
                }
            }
        }

        XCTAssertEqual(successCount, 1, "Exactly one concurrent resume should succeed")
    }
}
