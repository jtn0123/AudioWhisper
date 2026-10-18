import AppKit
import SwiftUI
import ViewInspector
import XCTest
@testable import AudioWhisper

@MainActor
final class SavedDictationModeTests: IsolatedXCTestCase {
    private var previous: DictationModeSettings!
    private var previousModes: [SavedDictationMode] = []
    private var previousID: UUID?

    override func setUp() {
        super.setUp()
        previous = AppDefaults.currentDictationSettings
        previousModes = AppDefaults.savedDictationModes
        previousID = AppDefaults.selectedDictationModeID
        AppDefaults.selectedDictationModeID = nil
        AppDefaults.savedDictationModes = []
    }

    override func tearDown() {
        AppDefaults.currentDictationSettings = previous
        AppDefaults.savedDictationModes = previousModes
        AppDefaults.selectedDictationModeID = previousID
        super.tearDown()
    }

    func testSavedSettingsSurvivePersistenceAndApplyTogether() throws {
        var settings = previous!
        settings.provider = .local
        settings.whisper = .tiny
        settings.cleanup = .off
        settings.vocabulary = "AudioWhisper\npost gress -> Postgres"
        settings.removeFillers.toggle()
        settings.spokenPunctuation.toggle()
        let mode = try SavedDictationMode.make(name: "  Project terms  ", settings: settings, existing: [])
        AppDefaults.savedDictationModes = [mode]
        let restored = try XCTUnwrap(AppDefaults.savedDictationModes.first)
        XCTAssertEqual(restored, mode)
        XCTAssertEqual(restored.name, "Project terms")
        let smartPaste = AppDefaults.enableSmartPaste
        let history = AppDefaults.transcriptionHistoryEnabled
        let microphone = AppDefaults.microphoneRanking
        AppDefaults.currentDictationSettings = restored.settings
        XCTAssertEqual(AppDefaults.currentDictationSettings, settings)
        XCTAssertEqual(AppDefaults.enableSmartPaste, smartPaste)
        XCTAssertEqual(AppDefaults.transcriptionHistoryEnabled, history)
        XCTAssertEqual(AppDefaults.microphoneRanking, microphone)
    }

    func testInvalidNamesAndDuplicatesCannotCreateAmbiguousModes() throws {
        let mode = try SavedDictationMode.make(name: "Work", settings: previous, existing: [])
        for name in [" ", "two\nlines", String(repeating: "a", count: 61)] {
            XCTAssertThrowsError(try SavedDictationMode.make(name: name, settings: previous, existing: []))
        }
        XCTAssertThrowsError(try SavedDictationMode.make(name: " work ", settings: previous, existing: [mode]))
        XCTAssertThrowsError(try SavedDictationMode.make(name: "Another", settings: previous,
                                                        existing: Array(repeating: mode, count: 32)))
    }

    func testUnreadableSavedDataFallsBackWithoutChangingCurrentSettings() {
        let corrupt = Data("incomplete settings".utf8)
        AppDefaults.defaults.set(corrupt, forKey: AppDefaults.Key.savedDictationModes.rawValue)
        XCTAssertTrue(AppDefaults.savedDictationModes.isEmpty)
        XCTAssertEqual(AppDefaults.currentDictationSettings, previous)
        XCTAssertEqual(AppDefaults.defaults.data(forKey: AppDefaults.Key.savedDictationModes.rawValue), corrupt)
    }

    func testModePickerAppliesSavedSettingsAndRemoveLeavesCurrentSetup() throws {
        var settings = previous!
        settings.removeFillers.toggle()
        let mode = try SavedDictationMode.make(name: "Project dictation", settings: settings, existing: [])
        AppDefaults.savedDictationModes = [mode]
        try RebuildModePicker(session: nil).inspect().find(ViewType.Picker.self).select(value: mode.id.uuidString)
        XCTAssertEqual(AppDefaults.currentDictationSettings, settings)
        let view = RebuildSavedModesView(session: nil)
        _ = try view.inspect().find(text: "Project dictation")
        if ProcessInfo.processInfo.environment["SAVE_MODE_PREVIEW"] == "1" { try capture(view) }
        try view.inspect().find(button: "Remove").tap()
        XCTAssertTrue(AppDefaults.savedDictationModes.isEmpty)
        XCTAssertEqual(AppDefaults.currentDictationSettings, settings)
    }

    func testModePickerCannotChangeARecordingInProgress() throws {
        var settings = previous!
        settings.provider = previous.provider == .local ? .parakeet : .local
        let mode = try SavedDictationMode.make(name: "Other engine", settings: settings, existing: [])
        AppDefaults.savedDictationModes = [mode]
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in true }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "Fixture", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }, capturePasteDestination: { nil }))
        session.readiness = RebuildReadiness(
            microphoneGranted: true, modelInstalled: true, runtimeReady: true, checking: false)
        session.toggleRecording()
        defer { session.cancel() }
        XCTAssertEqual(session.phase, .recording)
        let picker = try RebuildModePicker(session: session).inspect().find(ViewType.Picker.self)
        XCTAssertTrue(try picker.isDisabled())
        XCTAssertThrowsError(try picker.select(value: mode.id.uuidString))
        XCTAssertEqual(AppDefaults.currentDictationSettings, previous)
        XCTAssertFalse(session.readiness.checking)
    }

    func testSelectingSecondIdenticalModeKeepsItsName() throws {
        let first = try SavedDictationMode.make(name: "Work", settings: previous, existing: [])
        let second = try SavedDictationMode.make(name: "Personal", settings: previous, existing: [first])
        AppDefaults.savedDictationModes = [first, second]
        let picker = try RebuildModePicker(session: nil).inspect().find(ViewType.Picker.self)
        try picker.select(value: second.id.uuidString)
        XCTAssertEqual(try picker.selectedValue(String.self), second.id.uuidString)
        var changed = AppDefaults.currentDictationSettings
        changed.removeFillers.toggle()
        AppDefaults.currentDictationSettings = changed
        XCTAssertNil(AppDefaults.activeDictationModeID)
        XCTAssertEqual(try picker.selectedValue(String.self), "")
    }

    private func capture(_ view: some View) throws {
        let size = NSSize(width: 800, height: 420)
        let host = NSHostingView(rootView: view.padding(24).background(RebuildTheme.canvas))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/audiowhisper-saved-modes.png"))
    }
}
