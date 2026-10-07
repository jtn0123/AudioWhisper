import AppKit
import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildWorkspaceBehaviorTests: IsolatedXCTestCase {
    private var copied: [String] = []
    private var saved = 0
    private var cancelled = 0
    private var recordingStarted = 0
    private var handler: ((URL) async throws -> TranscriptionResult)?
    private var stopAudio: URL?

    private func session(ready: Bool = true) -> RebuildSession {
        AppDefaults.enableSmartPaste = false
        AppDefaults.playCompletionSound = false
        AppDefaults.transcriptionProvider = .local
        AppDefaults.selectedWhisperModel = .base
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in self.recordingStarted += 1; return true }, stop: { self.stopAudio },
            cancel: { self.cancelled += 1 },
            transcribe: { url, _, _ in
                if let handler = self.handler { return try await handler(url) }
                return TranscriptionResult(text: "Hello world.", correctionOutcome: .applied("Hello world."),
                                           originalText: "hello world")
            },
            copy: { self.copied.append($0) }, save: { _, _, _ in self.saved += 1 }),
            setup: RebuildSetupServices(
                selection: { .current }, microphoneStatus: { ready ? .authorized : .notDetermined },
                requestMicrophone: { _ in XCTFail("A view must not request real consent") }, openMicrophoneSettings: {},
                runtimeReady: { _ in true }, modelInstalled: { _ in ready },
                install: { _ in XCTFail("This fixture must not install real models") },
                verify: { _ in ModelVerificationResult(succeeded: true, message: "Fixture verified") }))
        session.readiness = RebuildReadiness(
            microphoneGranted: ready, modelInstalled: ready, runtimeReady: true, checking: false)
        return session
    }

    func testEverySidebarControlChangesSelectionAndSetupStatusHasItsOwnRoute() throws {
        let session = session(ready: false)
        let navigation = RebuildNavigation()
        let view = RebuildSidebar(session: session, navigation: navigation)
        for page in RebuildPage.allCases {
            try view.inspect().find(button: page.title).tap()
            XCTAssertEqual(navigation.selection, page)
        }
        navigation.selection = .record
        try view.inspect().find(button: session.readiness.nextStep).tap()
        XCTAssertEqual(navigation.selection, .models)
    }

    func testRecordSetupAndShortcutActionsAreVisibleAndDoNotStartHardware() throws {
        let session = session(ready: false)
        var setupOpened = 0
        var shortcutOpened = 0
        session.openSetup = { setupOpened += 1 }
        let view = RebuildRecordView(
            session: session, recorder: AudioEngineRecorder(), importAudio: {},
            configureShortcut: { shortcutOpened += 1 }, readShortcut: { nil })
        try view.inspect().find(button: "Open setup").tap()
        XCTAssertEqual(setupOpened, 1)
        try view.inspect().find(button: "Set up").tap()
        XCTAssertEqual(shortcutOpened, 1)
        XCTAssertEqual(recordingStarted, 0)
        _ = try view.inspect().find(text: "A little less typing.")
    }

    func testRecorderControlsFollowRecordingAndCancelDiscardsIt() throws {
        let session = session()
        session.toggleRecording()
        let view = RebuildRecorderView(session: session, recorder: AudioEngineRecorder())
        _ = try view.inspect().find(text: "Recording")
        XCTAssertFalse(try view.inspect().find(button: "Stop & transcribe").isDisabled())
        try view.inspect().find(button: "Cancel").tap()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertEqual(cancelled, 1)
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(saved, 0)
        XCTAssertTrue(try view.inspect().find(button: "Transcribing…").isDisabled())
    }

    func testOriginalRecoveryControlRestoresAndCopiesWithoutAnotherSave() async throws {
        let session = session()
        session.importAudio(URL(fileURLWithPath: "/unused-ui-fixture.wav"))
        try await waitFor { session.phase == .completed }
        let view = RebuildTranscriptCard(session: session)
        _ = try view.inspect().find(button: "Copy text")
        try view.inspect().find(button: "Use original").tap()
        XCTAssertEqual(session.transcript, "hello world")
        XCTAssertEqual(copied, ["Hello world.", "hello world"])
        XCTAssertEqual(saved, 1)
        XCTAssertThrowsError(try view.inspect().find(button: "Use original"))
    }

    func testPreferencesExposesRecordingDeliveryPrivacyAndAppearanceControls() throws {
        AppDefaults.pressAndHoldEnabled = true
        let view = RebuildPreferencesView()
        for label in [
            "Enable recording shortcut", "Record while holding a modifier key",
            "Express Mode · record without showing the overlay", "Boost microphone input while recording",
            "Play a completion sound", "Paste into the app I recorded from",
            "Save transcripts to my local library", "Open AudioWhisper at login"
        ] {
            _ = try view.inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == label })
        }
        _ = try view.inspect().find(button: "Check access")
        _ = try view.inspect().find(button: "Open System Settings")
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertTrue(condition(), "Session did not reach the required UI state")
    }
}

extension RebuildWorkspaceBehaviorTests {
    func testStartupPreservesSettingsOrdersItsEffectsAndRoutesSetupToTheWorkspace() async throws {
        let session = session(ready: false)
        let navigation = RebuildNavigation()
        AppDefaults.enableSmartPaste = true
        AppDefaults.pressAndHoldEnabled = true
        var effects: [String] = []
        RebuildStartup.configure(
            session: session, navigation: navigation,
            effects: .init(initializeHistory: { effects.append("history") }, migrateSettings: { effects.append("migration") },
            installMenu: { effects.append("menu") }, configureShortcuts: { effects.append("shortcuts") },
            showWorkspace: { effects.append("workspace") }, showRecorder: { effects.append("recorder") },
            closeRecorder: { effects.append("close recorder") }))
        XCTAssertEqual(effects, ["migration", "history", "menu", "shortcuts", "workspace"])
        XCTAssertTrue(AppDefaults.enableSmartPaste)
        XCTAssertTrue(AppDefaults.pressAndHoldEnabled)
        session.openSetup()
        XCTAssertEqual(navigation.selection, .models)
        XCTAssertEqual(effects.last, "workspace")
        session.showRecorder()
        session.closeRecorder()
        XCTAssertEqual(effects.suffix(2), ["recorder", "close recorder"])
        try await waitFor { !session.readiness.checking }
        XCTAssertFalse(session.readiness.ready)
    }

    func testStartupKeepsTheLibraryFailureVisibleAndStillPresentsTheWorkspace() {
        let session = session()
        var shown = 0
        RebuildStartup.configure(
            session: session, navigation: RebuildNavigation(),
            effects: .init(initializeHistory: {
                throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture storage unavailable"])
            },
            migrateSettings: {}, installMenu: {}, configureShortcuts: {},
            showWorkspace: { shown += 1 }, showRecorder: {}, closeRecorder: {}))
        XCTAssertTrue(session.notice?.contains("Fixture storage unavailable") == true)
        XCTAssertEqual(shown, 1)
    }

    func testNativeMenuCommandsRouteToTheSessionAndDisableImportWhileRecording() {
        _ = NSApplication.shared
        let session = session()
        var opened = 0
        var imported = 0
        let contents = RebuildStatusMenu(session: session, openWorkspace: { opened += 1 }, chooseAudio: { imported += 1 })
        contents.refresh()
        XCTAssertEqual(contents.recordItem.title, "Start recording")
        XCTAssertTrue(contents.recordItem.isEnabled)
        contents.menu.performActionForItem(at: 1)
        contents.menu.performActionForItem(at: 2)
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(imported, 1)
        contents.menu.performActionForItem(at: 0)
        XCTAssertEqual(session.phase, .recording)
        contents.refresh()
        XCTAssertEqual(contents.recordItem.title, "Finish recording")
        XCTAssertFalse(contents.menu.items[2].isEnabled)
        XCTAssertTrue(contents.menu.items[2].toolTip?.contains("recording") == true)
        session.cancel()
    }

    func testTranscribingHUDDisablesStopWhileCancelBlocksLateDelivery() async throws {
        var pending: CheckedContinuation<TranscriptionResult, Never>?
        var returned = false
        handler = { _ in
            let result = await withCheckedContinuation { pending = $0 }
            returned = true
            return result
        }
        stopAudio = FileManager.default.temporaryDirectory.appendingPathComponent("ui-stop-\(UUID()).wav")
        let session = session()
        session.toggleRecording()
        let view = RebuildRecorderView(session: session, recorder: AudioEngineRecorder())
        try view.inspect().find(button: "Stop & transcribe").tap()
        try await waitFor { pending != nil }
        XCTAssertTrue(try view.inspect().find(button: "Transcribing…").isDisabled())
        XCTAssertFalse(try view.inspect().find(button: "Cancel").isDisabled())
        try view.inspect().find(button: "Cancel").tap()
        try XCTUnwrap(pending).resume(returning: TranscriptionResult(text: "late result", correctionOutcome: nil))
        try await waitFor { returned }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(saved, 0)
    }

    func testWritingCleanupCannotBeEnabledUntilTheSelectedModelIsInstalled() throws {
        let session = session()
        AppDefaults.semanticCorrectionMode = .off
        let missing = RebuildWritingView(session: session, isModelCached: { _ in false })
        XCTAssertTrue(try missing.inspect().find(ViewType.Toggle.self).isDisabled())
        _ = try missing.inspect().find(button: "Install correction model")
        XCTAssertThrowsError(try missing.inspect().find(button: "Verify correction model"))
        let installed = RebuildWritingView(session: session, isModelCached: { _ in true })
        _ = try installed.inspect().find(text: "Installed on this Mac")
        _ = try installed.inspect().find(button: "Verify correction model")
        _ = try installed.inspect().find(button: "Remove…")
        if Arch.isAppleSilicon {
            try installed.inspect().find(ViewType.Toggle.self).tap()
            XCTAssertEqual(AppDefaults.semanticCorrectionMode, .localMLX)
        } else {
            XCTAssertTrue(try installed.inspect().find(ViewType.Toggle.self).isDisabled())
        }
    }

    func testWritingControlsAreDisabledWhileRecording() throws {
        let session = session()
        session.toggleRecording()
        let view = RebuildWritingView(session: session, isModelCached: { _ in true })
        XCTAssertTrue(try view.inspect().find(ViewType.Toggle.self).isDisabled())
        XCTAssertTrue(try view.inspect().find(button: "Verify correction model").isDisabled())
        XCTAssertTrue(try view.inspect().find(button: "Remove…").isDisabled())
        session.cancel()
    }

    func testWritingInstallControlReportsARealInstallerFailureWithoutEnablingCleanup() async throws {
        AppDefaults.semanticCorrectionMode = .off
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("ui-writing-\(UUID())")
        let manager = MLXModelManager(cacheDirectory: cache, prepareDownloadPython: {
            throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture offline"])
        })
        let installer = RebuildWritingInstaller(manager: manager)
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in false }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }), writingInstaller: installer)
        let view = RebuildWritingView(session: session, isModelCached: { _ in false })
        if !Arch.isAppleSilicon {
            XCTAssertTrue(try view.inspect().find(button: "Install correction model").isDisabled())
            return
        }
        try view.inspect().find(button: "Install correction model").tap()
        try await waitFor { !installer.isRunning && installer.status(for: AppDefaults.semanticCorrectionModelRepo) != nil }
        let status = try XCTUnwrap(installer.status(for: AppDefaults.semanticCorrectionModelRepo))
        XCTAssertTrue(status.contains("Fixture offline"), status)
        _ = try view.inspect().find(text: status)
        XCTAssertEqual(AppDefaults.semanticCorrectionMode, .off)
        XCTAssertFalse(session.maintenanceInProgress)
    }

    func testNativeContentControllerPreservesBoundsAcrossNoninteractivePages() throws {
        // Same unordered borderless hosting pattern as ViewBodyRenderingTests.
        // This doesn't register shortcuts, host Preferences' native recorder,
        // activate an app or replace the interactive VM/desktop fixture.
        _ = NSApplication.shared
        let session = session()
        let navigation = RebuildNavigation()
        navigation.selection = .models
        let controller = RebuildWorkspaceHosting.controller(for: RebuildRootView(
            session: session, navigation: navigation, recorder: AudioEngineRecorder(), importAudio: {},
            history: MockDataManager(), readShortcut: { nil }))
        XCTAssertTrue(controller.sizingOptions.isEmpty)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 870, height: 620),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 900, height: 650))
        defer { window.contentViewController = nil; window.close() }
        for page in [RebuildPage.models, .library, .record] {
            navigation.selection = page
            controller.view.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.size, NSSize(width: 900, height: 650))
            XCTAssertEqual(controller.view.frame.size, window.contentLayoutRect.size)
        }
    }
}
