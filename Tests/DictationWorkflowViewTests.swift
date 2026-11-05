import AppKit
import SwiftUI
import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class DictationWorkflowViewTests: IsolatedXCTestCase {
    func testModeEditorShowsEngineSpecificControlsAndValidatesEditsWithoutLosingIdentity() throws {
        var settings = AppDefaults.currentDictationSettings
        settings.provider = .local
        let mode = try SavedDictationMode.make(name: "Work", settings: settings, existing: [])
        AppDefaults.savedDictationModes = [mode]
        var saved: SavedDictationMode?
        let draft = RebuildModeDraft(mode: mode) { saved = $0 }
        draft.name = "Renamed work"
        draft.settings.language = .french
        draft.settings.writing.instructions = "Use short paragraphs."
        XCTAssertTrue(draft.commit())
        XCTAssertEqual(saved?.id, mode.id)
        XCTAssertEqual(saved?.name, "Renamed work")
        XCTAssertEqual(saved?.settings.language, .french)
        draft.settings.writing.instructions = String(repeating: "x", count: 4_001)
        XCTAssertFalse(draft.commit())
        XCTAssertNotNil(draft.error)
        XCTAssertEqual(saved?.settings.writing.instructions, "Use short paragraphs.")
        draft.settings.writing.instructions = ""
        draft.name = ""
        XCTAssertFalse(draft.commit())
        for provider in [TranscriptionProvider.local, .parakeet] {
            settings.provider = provider
            let configured = SavedDictationMode(id: mode.id, name: mode.name, settings: settings)
            let view = RebuildModeEditor(mode: configured, save: { _ in })
            assertLayout(view)
            _ = try view.inspect().find(text: "Edit dictation mode")
            _ = try view.inspect().find(button: "Save changes")
            let labels = try view.inspect().findAll(ViewType.Picker.self).map { try $0.labelView().text().string() }
            XCTAssertEqual(labels.contains("Language"), provider == .local)
            XCTAssertEqual(labels.contains("Parakeet model"), provider == .parakeet)
        }
    }

    func testAppRuleControlsChangeOnlyTheirRule() throws {
        let first = try SavedDictationMode.make(name: "First", settings: AppDefaults.currentDictationSettings, existing: [])
        let second = try SavedDictationMode.make(name: "Second", settings: first.settings, existing: [first])
        AppDefaults.savedDictationModes = [first, second]
        AppDefaults.appDictationRules = [.init(bundleIdentifier: "fixture.mail", appName: "Fixture Mail", modeID: first.id)]
        let view = RebuildAppRulesView(session: nil)
        assertLayout(view)
        try view.inspect().find(ViewType.Toggle.self).tap()
        XCTAssertFalse(AppDefaults.appDictationRules[0].enabled)
        try view.inspect().find(ViewType.Picker.self).select(value: second.id)
        XCTAssertEqual(AppDefaults.appDictationRules[0].modeID, second.id)
        try view.inspect().find(button: "Remove").tap()
        XCTAssertTrue(AppDefaults.appDictationRules.isEmpty)
        AppDefaults.savedDictationModes = []
        XCTAssertTrue(try RebuildAppRulesView(session: nil).inspect().find(button: "Add app…").isDisabled())
    }

    func testHistoryCleanupPreviewRequiresExplicitSaveAndShowsFailureWithoutReplacingOriginal() async throws {
        var settings = AppDefaults.currentDictationSettings
        settings.cleanup = .localMLX
        AppDefaults.currentDictationSettings = settings
        let original = TranscriptionRecord(text: "First result", provider: .local, originalText: "Original fixture")
        let state = RebuildHistoryCleanup(record: original, history: MockDataManager(), session: nil) { text, _ in
            TranscriptionResult(text: "A revised result", correctionOutcome: .applied("A revised result"), originalText: text)
        }
        let view = RebuildHistoryCleanupView(state: state)
        assertLayout(view)
        try view.inspect().find(button: "Run cleanup").tap()
        try await wait { !state.running }
        XCTAssertEqual(state.result, "A revised result")
        _ = try view.inspect().find(text: "New version · Preview")
        XCTAssertFalse(state.saved)
        XCTAssertEqual(original.text, "First result")
        try view.inspect().find(button: "Save version").tap()
        try await wait { state.error != nil }
        XCTAssertFalse(state.saved, "An unavailable history container must not claim that a version was saved")
        assertLayout(view)
        try view.inspect().find(button: "Close").tap()
    }

    func testMeetingsShowRecoveryRetentionAndTranscriptActionsWithoutOpeningDevices() throws {
        let store = MeetingStore(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        defer { try? FileManager.default.removeItem(at: store.root) }
        let state = RebuildMeetingSession(dictation: nil, store: store)
        state.microphone = false
        state.systemAudio = false
        let view = RebuildMeetingsView(state: state)
        assertLayout(view)
        XCTAssertTrue(try view.inspect().find(button: "Start meeting").isDisabled())
        var document = MeetingDocument(title: "Design review")
        document.status = .complete
        document.audioRetained = false
        document.segments = [.init(source: .microphone, start: 2, end: 5, text: "Review the draft.", speaker: "Cluster 0")]
        document.summary = "Decision: review the draft."
        document.note = "Speaker estimates need review."
        try store.save(document)
        state.refresh()
        state.open(document.id)
        state.makeSummary = true
        state.speakerModelFolder = "/fixture/speaker"
        state.error = "Fixture warning"
        assertLayout(view)
        _ = try view.inspect().find(text: "Source audio deleted after processing")
        _ = try view.inspect().find(button: "Copy transcript")
        _ = try view.inspect().find(button: "Export transcript…")
        XCTAssertTrue(try view.inspect().find(button: "Process captured audio").isDisabled())
        try view.inspect().find(button: "Turn off").tap()
        XCTAssertNil(state.speakerModelFolder)
        try view.inspect().find(button: "Delete meeting…").tap()
        XCTAssertNotNil(state.document, "Delete must wait for the destructive confirmation")
        state.deleteCurrent()
        XCTAssertNil(state.document)
        XCTAssertTrue(state.documents.isEmpty)
    }

    private func assertLayout(_ view: some View, file: StaticString = #filePath, line: UInt = #line) {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 760),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(host.fittingSize.width, 0, file: file, line: line)
        XCTAssertGreaterThan(host.fittingSize.height, 0, file: file, line: line)
        window.contentView = nil
        window.close()
    }

    private func wait(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 where !condition() { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(condition())
    }
}
