import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildPreferencesBehaviorTests: IsolatedXCTestCase {
    private var allowed = false
    private var settingsOpened = 0
    private var loginChanges: [Bool] = []
    private var loginFails = false
    private var cleanups = 0
    private var cleanupFails = false
    private var copied: [String] = []
    private var recalculations = 0
    private var resets = 0

    private func state() -> RebuildPreferencesState {
        RebuildPreferencesState(effects: RebuildPreferencesEffects(
            checkAccess: { self.allowed }, openAccessSettings: { self.settingsOpened += 1 },
            changeLogin: { enabled in
                self.loginChanges.append(enabled)
                if self.loginFails { throw self.error("Fixture login rejected") }
            }, loginEnabled: { false }, cleanupRetention: {
                self.cleanups += 1
                if self.cleanupFails { throw self.error("Fixture cleanup failed") }
            }, diagnostics: { "public fixture diagnostics" }, copy: { self.copied.append($0) },
            recalculate: { self.recalculations += 1; throw self.error("Fixture calculation failed") },
            resetUsage: { self.resets += 1 }))
    }

    private func error(_ message: String) -> NSError {
        NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    func testAccessCheckRefreshesStatusAndOpenSettingsUsesOnlyTheExplicitButton() throws {
        let state = state()
        let view = RebuildPreferencesView(state: state)
        _ = try view.inspect().find(text: "Not enabled")
        allowed = true
        try view.inspect().find(button: "Check access").tap()
        _ = try view.inspect().find(text: "Allowed")
        XCTAssertEqual(settingsOpened, 0)
        try view.inspect().find(button: "Open System Settings").tap()
        XCTAssertEqual(settingsOpened, 1)
        XCTAssertFalse(state.refreshAccess(), "An unchanged check must not reconfigure global keys")
    }

    func testLoginFailureRollsBackTheDisplayedPreferenceAndCanBeDismissed() throws {
        let state = state()
        let view = RebuildPreferencesView(state: state)
        AppDefaults.startAtLogin = true
        loginFails = true
        try view.inspect().scrollView().callOnChange(oldValue: false, newValue: true, index: 2)
        XCTAssertEqual(loginChanges, [true])
        XCTAssertFalse(AppDefaults.startAtLogin)
        _ = try view.inspect().find(text: "Login setting could not be updated: Fixture login rejected")
        try view.inspect().find(button: "Dismiss").tap()
        XCTAssertNil(state.message)
        loginFails = false
        try view.inspect().scrollView().callOnChange(oldValue: true, newValue: false, index: 2)
        XCTAssertEqual(loginChanges, [true, false])
        XCTAssertNil(state.message)
    }

    func testRetentionChangeSurfacesCleanupFailure() async throws {
        let state = state()
        cleanupFails = true
        let view = RebuildPreferencesView(state: state)
        try view.inspect().scrollView().callOnChange(oldValue: RetentionPeriod.forever, newValue: RetentionPeriod.oneWeek)
        try await waitFor { state.message != nil }
        _ = try view.inspect().find(text: "Retention cleanup failed: Fixture cleanup failed")
        XCTAssertEqual(cleanups, 1)
    }

    func testAdvancedToolsOpenCopyPublicDiagnosticsAndReportRecalculationFailure() async throws {
        let state = state()
        let view = RebuildPreferencesView(state: state)
        try view.inspect().find(ViewType.Button.self, where: {
            (try? $0.accessibilityLabel().string()) == "Advanced and support"
        }).tap()
        XCTAssertTrue(state.showAdvanced)
        try view.inspect().find(button: "Copy setup diagnostics").tap()
        try await waitFor { !self.copied.isEmpty }
        XCTAssertEqual(copied, ["public fixture diagnostics"])
        _ = try view.inspect().find(text: "Setup diagnostics copied. No transcripts or history are included.")
        AppDefaults.transcriptionHistoryEnabled = false
        XCTAssertTrue(try RebuildPreferencesView(state: state).inspect()
            .find(button: "Recalculate from saved history").isDisabled())
        AppDefaults.transcriptionHistoryEnabled = true
        try RebuildPreferencesView(state: state).inspect().find(button: "Recalculate from saved history").tap()
        try await waitFor { self.recalculations == 1 && state.message?.contains("Fixture calculation failed") == true }
        _ = try view.inspect().find(text: "Usage could not be recalculated: Fixture calculation failed")
        try view.inspect().find(button: "Reset…").tap()
        XCTAssertTrue(state.resetUsage)
        XCTAssertEqual(resets, 0)
        let container = try view.inspect().find(ViewType.VStack.self, where: { (try? $0.confirmationDialog()) != nil })
        try container.confirmationDialog().actions().find(button: "Reset totals").tap()
        XCTAssertEqual(resets, 1)
    }

    func testLiveDiagnosticsSerializeOnlySetupMetadata() async throws {
        let diagnostics = await RebuildPreferencesEffects.live.diagnostics()
        let text = try XCTUnwrap(diagnostics)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertNotNil(object["readyToRecord"])
        XCTAssertNil(object["transcripts"])
        XCTAssertNil(object["history"])
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition())
    }
}
