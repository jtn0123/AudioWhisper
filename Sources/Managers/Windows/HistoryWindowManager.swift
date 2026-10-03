import Foundation
import AppKit
import SwiftUI
import SwiftData
import os.log

/// Manages the transcription history window lifecycle to prevent memory leaks
/// and ensure only one instance exists at a time
@MainActor
internal final class HistoryWindowManager: NSObject {
    static let shared = HistoryWindowManager()

    /// Held strongly until it closes; see `DashboardWindowManager`.
    private var historyWindow: NSWindow?
    private var windowDelegate: StandardWindowDelegate?
    private let isTestEnvironment: Bool

    private override init() {
        isTestEnvironment = AppEnvironment.isRunningTests
        super.init()
    }

    /// Shows the history window, creating it if necessary or bringing existing one to front
    func showHistoryWindow() {
        // Skip actual window operations in test environment
        if isTestEnvironment {
            return
        }

        if let existingWindow = historyWindow {
            StandardWindow.present(existingWindow)
            return
        }

        // Create new window - need a valid ModelContainer
        guard let container = DataManager.shared.sharedModelContainer ?? createFallbackContainer() else {
            Logger.app.error("Cannot show history window: Failed to create ModelContainer")
            return
        }

        let historyView = TranscriptionHistoryView()
            .modelContainer(container)

        let hostingController = NSHostingController(rootView: historyView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.contentViewController = hostingController
        window.title = "Transcription History"
        window.setContentSize(NSSize(width: 800, height: 500))
        window.minSize = NSSize(width: 700, height: 400)

        historyWindow = window
        windowDelegate = StandardWindow.open(window, frameAutosaveName: "AudioWhisperHistory") { [weak self] in
            self?.windowWillClose()
        }

        Logger.app.info("History window created and shown")
    }

    /// Called when the history window is closing
    func windowWillClose() {
        // Clean up references
        historyWindow = nil
        windowDelegate = nil
        Logger.app.info("History window closed and references cleaned up")
    }

    /// Creates a fallback container if DataManager isn't initialized
    private func createFallbackContainer() -> ModelContainer? {
        let schema = Schema([TranscriptionRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            Logger.app.error("Failed to create fallback ModelContainer with schema configuration: \(error)")
        }

        do {
            return try ModelContainer(
                for: TranscriptionRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            Logger.app.critical("All ModelContainer creation attempts failed: \(error)")
        }

        return nil
    }
}
