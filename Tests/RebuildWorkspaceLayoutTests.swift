import AppKit
import SwiftData
import XCTest
@testable import AudioWhisper

@MainActor
final class RebuildWorkspaceLayoutTests: IsolatedXCTestCase {
    func testPopulatedLibraryAndPageTransitionsKeepTheUserWindowSize() async throws {
        // Hosted runners can report a display without an interactive window
        // server (see WindowServer's probe caveat). Exercise this desktop
        // fixture locally; packaged VM acceptance supplies separate native evidence.
        try XCTSkipIf(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
                      "Native workspace hosting requires an interactive macOS desktop")
        try XCTSkipUnless(WindowServer.hasActiveDisplay, "Hosting layout requires a WindowServer")
        // Each parallel XCTest worker starts without the app's entry point.
        // Initialize AppKit before creating a native window on older macOS.
        _ = NSApplication.shared
        let shortcutKey = "KeyboardShortcuts_rebuild.recording"
        let previousShortcut = UserDefaults.standard.object(forKey: shortcutKey)
        defer { UserDefaults.standard.set(previousShortcut, forKey: shortcutKey) }
        AppDefaults.transcriptionHistoryEnabled = true
        AppDefaults.transcriptionRetentionPeriod = .forever
        let container = try ModelContainer(
            for: TranscriptionRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let history = DataManager(modelContainer: container)
        for index in 0..<55 {
            try await history.saveTranscription(TranscriptionRecord(
                text: "Transcript \(index)\n" + String(repeating: "Long words and paragraphs.\n", count: 12),
                provider: .local, originalText: "The original words before cleanup."))
        }
        let navigation = RebuildNavigation()
        let session = RebuildSession(services: RebuildSessionServices(
            start: { _ in false }, stop: { nil }, cancel: {},
            transcribe: { _, _, _ in TranscriptionResult(text: "unused", correctionOutcome: nil) },
            copy: { _ in }, save: { _, _, _ in }))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 870, height: 598),
            styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.minSize = NSSize(width: 870, height: 620)
        window.contentViewController = RebuildWorkspaceHosting.controller(for: RebuildRootView(
            session: session, navigation: navigation, recorder: AudioEngineRecorder(), importAudio: {}, history: history))
        window.setFrame(NSRect(x: 10, y: 50, width: 870, height: 620), display: false)
        for page in [RebuildPage.library, .record, .preferences, .writing, .models, .library] {
            navigation.selection = page
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(350))
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(window.frame.size, NSSize(width: 870, height: 620), "Page \(page) changed the window")
            XCTAssertLessThanOrEqual(window.contentMinSize.height, window.contentLayoutRect.height,
                                     "Content must not dictate a larger minimum height")
        }
        try await history.deleteAllRecords()
        try await Task.sleep(for: .milliseconds(350))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertEqual(window.frame.size, NSSize(width: 870, height: 620), "Empty Library changed the window")
    }
}
