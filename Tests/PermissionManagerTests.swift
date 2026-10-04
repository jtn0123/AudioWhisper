import XCTest
@testable import AudioWhisper

@MainActor
final class PermissionManagerTests: IsolatedXCTestCase {
    // Deferred(D1): PermissionManager and its call sites read `enableSmartPaste`
    // from UserDefaults.standard directly. Once they accept an injected
    // UserDefaults, route writes through a UUID-scoped suite and re-enable.
    override var enforcesStandardUserDefaultsIsolation: Bool { false }

    var permissionManager: PermissionManager!

    override func setUp() {
        super.setUp()
        permissionManager = PermissionManager()
    }

    override func tearDown() {
        permissionManager = nil
        super.tearDown()
    }

    // MARK: - PermissionState Tests

    func testPermissionStateNeedsRequest() {
        XCTAssertTrue(PermissionState.unknown.needsRequest)
        XCTAssertTrue(PermissionState.notRequested.needsRequest)
        XCTAssertFalse(PermissionState.requesting.needsRequest)
        XCTAssertFalse(PermissionState.granted.needsRequest)
        XCTAssertFalse(PermissionState.denied.needsRequest)
        XCTAssertFalse(PermissionState.restricted.needsRequest)
    }

    func testPermissionStateCanRetry() {
        XCTAssertFalse(PermissionState.unknown.canRetry)
        XCTAssertFalse(PermissionState.notRequested.canRetry)
        XCTAssertFalse(PermissionState.requesting.canRetry)
        XCTAssertFalse(PermissionState.granted.canRetry)
        XCTAssertTrue(PermissionState.denied.canRetry)
        XCTAssertFalse(PermissionState.restricted.canRetry)
    }

    // MARK: - PermissionManager Initial State Tests

    func testInitialState() {
        // After init, permission states reflect actual system status (not .unknown)
        // We verify the states are valid and modals are not shown
        let validMicStates: [PermissionState] = [.granted, .denied, .restricted, .notRequested, .unknown]
        let validAccessStates: [PermissionState] = [.granted, .notRequested, .unknown]
        XCTAssertTrue(validMicStates.contains(permissionManager.microphonePermissionState))
        XCTAssertTrue(validAccessStates.contains(permissionManager.accessibilityPermissionState))
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    // MARK: - Modal State Logic Tests

    func testRequestPermissionWithEducationForNewPermission() {
        permissionManager.microphonePermissionState = .notRequested

        permissionManager.requestPermissionWithEducation()

        XCTAssertTrue(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    func testRequestPermissionWithEducationForDeniedPermission() {
        AppDefaults.defaults.set(false, forKey: "enableSmartPaste")
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }

        permissionManager.microphonePermissionState = .denied

        permissionManager.requestPermissionWithEducation()

        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertTrue(permissionManager.showRecoveryModal)
    }

    func testRequestPermissionWithEducationForGrantedPermission() {
        permissionManager.microphonePermissionState = .granted
        permissionManager.accessibilityPermissionState = .granted

        permissionManager.requestPermissionWithEducation()

        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    // MARK: - State Transition Tests

    func testStateTransitions() {
        // Test valid state transitions for microphone permission
        permissionManager.microphonePermissionState = .unknown
        XCTAssertEqual(permissionManager.microphonePermissionState, .unknown)

        permissionManager.microphonePermissionState = .notRequested
        XCTAssertEqual(permissionManager.microphonePermissionState, .notRequested)

        permissionManager.microphonePermissionState = .requesting
        XCTAssertEqual(permissionManager.microphonePermissionState, .requesting)

        permissionManager.microphonePermissionState = .granted
        XCTAssertEqual(permissionManager.microphonePermissionState, .granted)

        permissionManager.microphonePermissionState = .denied
        XCTAssertEqual(permissionManager.microphonePermissionState, .denied)

        permissionManager.microphonePermissionState = .restricted
        XCTAssertEqual(permissionManager.microphonePermissionState, .restricted)

        // Test valid state transitions for accessibility permission
        permissionManager.accessibilityPermissionState = .unknown
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .unknown)

        permissionManager.accessibilityPermissionState = .notRequested
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .notRequested)

        permissionManager.accessibilityPermissionState = .requesting
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .requesting)

        permissionManager.accessibilityPermissionState = .granted
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .granted)

        permissionManager.accessibilityPermissionState = .denied
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .denied)

        permissionManager.accessibilityPermissionState = .restricted
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .restricted)
    }

    func testModalStateManagement() {
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)

        permissionManager.showEducationalModal = true
        XCTAssertTrue(permissionManager.showEducationalModal)

        permissionManager.showRecoveryModal = true
        XCTAssertFalse(permissionManager.showRecoveryModal, "Permission sheets cannot be presented concurrently")

        permissionManager.showEducationalModal = false
        permissionManager.showRecoveryModal = true
        XCTAssertTrue(permissionManager.showRecoveryModal)
        permissionManager.showRecoveryModal = false
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    // MARK: - Edge Cases

    func testRequestPermissionInRestrictedState() {
        AppDefaults.defaults.set(false, forKey: "enableSmartPaste")
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }

        permissionManager.microphonePermissionState = .restricted

        permissionManager.requestPermissionWithEducation()

        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    func testRequestPermissionWhileAlreadyRequesting() {
        AppDefaults.defaults.set(false, forKey: "enableSmartPaste")
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }

        permissionManager.microphonePermissionState = .requesting

        permissionManager.requestPermissionWithEducation()

        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    // MARK: - Performance Tests

    func testPermissionStateCheckPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = PermissionState.unknown.needsRequest
                _ = PermissionState.denied.canRetry
                _ = PermissionState.granted.needsRequest
            }
        }
    }

    // MARK: - Multiple Instance Tests

    func testMultiplePermissionManagerInstances() {
        let manager1 = PermissionManager()
        let manager2 = PermissionManager()

        manager1.microphonePermissionState = .granted
        manager2.microphonePermissionState = .denied

        XCTAssertEqual(manager1.microphonePermissionState, .granted)
        XCTAssertEqual(manager2.microphonePermissionState, .denied)

        manager1.showEducationalModal = true
        manager2.showRecoveryModal = true

        XCTAssertTrue(manager1.showEducationalModal)
        XCTAssertFalse(manager1.showRecoveryModal)
        XCTAssertFalse(manager2.showEducationalModal)
        XCTAssertTrue(manager2.showRecoveryModal)
    }

    // MARK: - AllPermissionsGranted Tests

    func testAllPermissionsGrantedWithSmartPasteDisabled() {
        // When SmartPaste is disabled, only microphone permission is required
        AppDefaults.defaults.set(false, forKey: "enableSmartPaste")

        permissionManager.microphonePermissionState = .granted
        permissionManager.accessibilityPermissionState = .denied

        XCTAssertTrue(permissionManager.allPermissionsGranted)

        // Clean up
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
    }

    func testAllPermissionsGrantedWithSmartPasteEnabled() {
        // When SmartPaste is enabled, both microphone and accessibility permissions are required
        AppDefaults.defaults.set(true, forKey: "enableSmartPaste")

        permissionManager.microphonePermissionState = .granted
        permissionManager.accessibilityPermissionState = .denied

        XCTAssertFalse(permissionManager.allPermissionsGranted)

        permissionManager.accessibilityPermissionState = .granted
        XCTAssertTrue(permissionManager.allPermissionsGranted)

        // Clean up
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
    }

    func testAllPermissionsGrantedWithMicrophoneDenied() {
        // Microphone permission is always required
        AppDefaults.defaults.set(false, forKey: "enableSmartPaste")

        permissionManager.microphonePermissionState = .denied
        permissionManager.accessibilityPermissionState = .granted

        XCTAssertFalse(permissionManager.allPermissionsGranted)

        // Clean up
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
    }

    // MARK: - SmartPaste Permission Logic Tests

    func testRequestPermissionWithSmartPasteEnabled() {
        AppDefaults.defaults.set(true, forKey: "enableSmartPaste")

        permissionManager.microphonePermissionState = .notRequested
        permissionManager.accessibilityPermissionState = .notRequested

        permissionManager.requestPermissionWithEducation()

        XCTAssertTrue(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)

        // Clean up
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
    }

    func testRequestPermissionWithSmartPasteDisabled() {
        AppDefaults.defaults.set(false, forKey: "enableSmartPaste")

        permissionManager.microphonePermissionState = .notRequested
        permissionManager.accessibilityPermissionState = .denied  // This should be ignored

        permissionManager.requestPermissionWithEducation()

        XCTAssertTrue(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)

        // Clean up
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
    }

    func testRequestPermissionWithMixedStates() {
        AppDefaults.defaults.set(true, forKey: "enableSmartPaste")

        permissionManager.microphonePermissionState = .granted
        permissionManager.accessibilityPermissionState = .denied

        permissionManager.requestPermissionWithEducation()

        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertTrue(permissionManager.showRecoveryModal)

        // Clean up
        AppDefaults.defaults.removeObject(forKey: "enableSmartPaste")
    }

}

extension PermissionManagerTests {
    // MARK: - Permission Request Coordination

    func testRepeatedProceedRequestsEnterRequestingSynchronously() async throws {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        permissionManager.microphonePermissionState = .notRequested
        permissionManager.accessibilityPermissionState = .notRequested

        for _ in 0..<5 {
            permissionManager.proceedWithPermissionRequest()
            permissionManager.requestPermissionWithEducation()
        }

        XCTAssertEqual(permissionManager.microphonePermissionState, .requesting)
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .notRequested)
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
        XCTAssertFalse(permissionManager.showAccessibilityModal)

        try await waitForMicrophoneRequestToFinish()
        XCTAssertEqual(permissionManager.microphonePermissionState, .denied)
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .notRequested,
                       "A denied microphone must not start the optional Accessibility request")
        XCTAssertFalse(permissionManager.showRecoveryModal,
                       "The result stays inline until the user explicitly asks for recovery")
        XCTAssertFalse(permissionManager.showAccessibilityModal)
    }

    func testPermissionEducationDoesNotInterruptMicrophoneRequestWithSmartPasteEnabled() {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        permissionManager.microphonePermissionState = .requesting
        permissionManager.accessibilityPermissionState = .notRequested

        permissionManager.requestPermissionWithEducation()

        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
        XCTAssertFalse(permissionManager.showAccessibilityModal)
    }

    func testPermissionEducationDoesNotInterruptAccessibilityRequest() {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        permissionManager.microphonePermissionState = .notRequested
        permissionManager.accessibilityPermissionState = .requesting

        permissionManager.requestPermissionWithEducation()
        permissionManager.proceedWithPermissionRequest()

        XCTAssertEqual(permissionManager.microphonePermissionState, .notRequested)
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .requesting)
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
        XCTAssertFalse(permissionManager.showAccessibilityModal)
    }

    func testRefreshingPermissionsPreservesAccessibilityRequestInProgress() {
        permissionManager.accessibilityPermissionState = .requesting

        permissionManager.checkPermissionState()

        XCTAssertEqual(permissionManager.accessibilityPermissionState, .requesting)
    }

    func testDirectSheetBindingsCannotStackPermissionModals() {
        permissionManager.microphonePermissionState = .granted
        permissionManager.accessibilityPermissionState = .notRequested
        permissionManager.showAccessibilityModal = true

        permissionManager.showEducationalModal = true
        permissionManager.showRecoveryModal = true

        XCTAssertTrue(permissionManager.showAccessibilityModal)
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)

        permissionManager.showAccessibilityModal = false
        permissionManager.showEducationalModal = true
        permissionManager.showAccessibilityModal = false

        XCTAssertTrue(permissionManager.showEducationalModal,
                      "A stale dismissal from the earlier Accessibility sheet must not close the current sheet")
    }

    func testDirectSheetBindingsCannotPresentDuringSystemPermissionRequest() {
        permissionManager.microphonePermissionState = .requesting

        permissionManager.showEducationalModal = true
        permissionManager.showRecoveryModal = true
        permissionManager.showAccessibilityModal = true

        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
        XCTAssertFalse(permissionManager.showAccessibilityModal)
    }

    func testProceedWithGrantedMicrophoneShowsOnlyAccessibilityExplanation() {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        permissionManager.microphonePermissionState = .granted
        permissionManager.accessibilityPermissionState = .notRequested
        permissionManager.showEducationalModal = true

        permissionManager.proceedWithPermissionRequest()
        permissionManager.proceedWithPermissionRequest()
        permissionManager.requestPermissionWithEducation()

        XCTAssertEqual(permissionManager.microphonePermissionState, .granted)
        XCTAssertTrue(permissionManager.showAccessibilityModal)
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    func testActiveAccessibilityExplanationPreventsRecoveryOrAnotherMicrophoneRequest() async throws {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        permissionManager.microphonePermissionState = .notRequested
        permissionManager.accessibilityPermissionState = .denied
        permissionManager.showAccessibilityModal = true

        permissionManager.requestPermissionWithEducation()
        permissionManager.proceedWithPermissionRequest()
        // The old implementation queued another request even while a sheet was open.
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(permissionManager.microphonePermissionState, .notRequested)
        XCTAssertTrue(permissionManager.showAccessibilityModal)
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
    }

    func testRepeatedProceedWithGrantedPermissionsDoesNotRequestAgain() async throws {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        permissionManager.microphonePermissionState = .granted
        permissionManager.accessibilityPermissionState = .granted

        for _ in 0..<5 {
            permissionManager.proceedWithPermissionRequest()
        }
        try await Task.sleep(for: .milliseconds(150))

        XCTAssertEqual(permissionManager.microphonePermissionState, .granted)
        XCTAssertEqual(permissionManager.accessibilityPermissionState, .granted)
        XCTAssertFalse(permissionManager.showEducationalModal)
        XCTAssertFalse(permissionManager.showRecoveryModal)
        XCTAssertFalse(permissionManager.showAccessibilityModal)
    }

    func testDeniedMicrophoneStopsBeforeAccessibilityAndOffersExplicitRecovery() async throws {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        permissionManager.microphonePermissionState = .notRequested
        permissionManager.accessibilityPermissionState = .notRequested

        permissionManager.proceedWithPermissionRequest()
        try await waitForMicrophoneRequestToFinish()

        XCTAssertFalse(permissionManager.showRecoveryModal)
        XCTAssertFalse(permissionManager.showAccessibilityModal)

        permissionManager.requestPermissionWithEducation()

        XCTAssertTrue(permissionManager.showRecoveryModal)
        XCTAssertFalse(permissionManager.showEducationalModal,
                       "A denied microphone must be recovered before optional Accessibility setup")
        XCTAssertFalse(permissionManager.showAccessibilityModal)
    }

    func testFiveRequestsShareOneAuthorizationAndGrantShowsOneOptionalExplanation() async {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        var requestCount = 0
        var response: (@Sendable (Bool) -> Void)?
        let manager = PermissionManager(microphoneRequest: { completion in
            requestCount += 1
            response = completion
        })
        manager.microphonePermissionState = .notRequested
        manager.accessibilityPermissionState = .notRequested
        for _ in 0..<5 {
            manager.proceedWithPermissionRequest()
        }
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(manager.microphonePermissionState, .requesting)
        XCTAssertFalse(manager.showAccessibilityModal)
        response?(true)
        for _ in 0..<20 where manager.microphonePermissionState == .requesting { await Task.yield() }
        XCTAssertEqual(manager.microphonePermissionState, .granted)
        XCTAssertTrue(manager.showAccessibilityModal)
        XCTAssertFalse(manager.showRecoveryModal)
        XCTAssertFalse(manager.showEducationalModal)
    }

    func testSetupMicrophoneGrantDoesNotAskForOptionalAccessibility() async {
        AppDefaults.enableSmartPaste = true
        defer { AppDefaults.defaults.removeObject(forKey: "enableSmartPaste") }
        var requestCount = 0
        var response: (@Sendable (Bool) -> Void)?
        let manager = PermissionManager(microphoneRequest: { completion in
            requestCount += 1
            response = completion
        })
        manager.microphonePermissionState = .notRequested
        manager.accessibilityPermissionState = .notRequested
        for _ in 0..<5 { manager.requestMicrophonePermission() }
        XCTAssertEqual(requestCount, 1)
        response?(true)
        for _ in 0..<20 where manager.microphonePermissionState == .requesting { await Task.yield() }
        XCTAssertEqual(manager.microphonePermissionState, .granted)
        XCTAssertFalse(manager.showAccessibilityModal)
        XCTAssertFalse(manager.showRecoveryModal)
        XCTAssertFalse(manager.showEducationalModal)
    }

    private func waitForMicrophoneRequestToFinish() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while permissionManager.microphonePermissionState != .denied && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(permissionManager.microphonePermissionState, .denied,
                       "The simulated microphone request should complete within the test budget")
    }
}
