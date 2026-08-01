import Foundation
import AppKit
import SwiftUI
import os.log

/// Protocol for dashboard window management, enabling dependency injection for testing
@MainActor
internal protocol DashboardWindowManaging {
    func showDashboardWindow()
}

/// Manages the dashboard window lifecycle
@MainActor
internal final class DashboardWindowManager: NSObject, DashboardWindowManaging {
    static let shared = DashboardWindowManager()

    private weak var dashboardWindow: NSWindow?
    private var windowDelegate: DashboardWindowDelegate?
    private let isTestEnvironment: Bool

    /// Most-recent transcripts, newest first. Read synchronously by the status
    /// menu's "Recent" section; refreshed via `refreshRecentRecordsCache()`.
    private(set) var recentRecordsCache: [TranscriptionRecord] = []

    private override init() {
        isTestEnvironment = AppEnvironment.isRunningTests
        super.init()
    }

    /// Returns up to `limit` most-recent cached records. Empty until the
    /// cache is first populated — callers degrade gracefully.
    func cachedRecentRecords(limit: Int) -> [TranscriptionRecord] {
        Array(recentRecordsCache.prefix(limit))
    }

    /// Reloads the recent-records cache from the data layer.
    func refreshRecentRecordsCache() async {
        let records = await DataManager.shared.fetchAllRecordsQuietly()
        recentRecordsCache = records
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    /// Shows the dashboard window, creating it if necessary or bringing existing one to front
    func showDashboardWindow() {
        if isTestEnvironment {
            return
        }

        if let existingWindow = dashboardWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let dashboardView = DashboardView()
            .environment(MLXModelManager.shared)
            .environment(PermissionManager.shared)

        let hostingController = NSHostingController(rootView: dashboardView)
        let initialSize = LayoutMetrics.DashboardWindow.initialSize
        let minimumSize = LayoutMetrics.DashboardWindow.minimumSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.contentViewController = hostingController
        window.title = "AudioWhisper Dashboard"
        window.setContentSize(initialSize)
        window.minSize = minimumSize
        window.center()
        window.isReleasedWhenClosed = false
        window.isRestorable = false

        // Follow system appearance
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        windowDelegate = DashboardWindowDelegate(manager: self)
        window.delegate = windowDelegate

        dashboardWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Logger.app.info("Dashboard window created and shown")
    }

    func windowWillClose() {
        dashboardWindow = nil
        windowDelegate = nil
        Logger.app.info("Dashboard window closed and references cleaned up")
    }
}

private class DashboardWindowDelegate: NSObject, NSWindowDelegate {
    private weak var manager: DashboardWindowManager?

    init(manager: DashboardWindowManager) {
        self.manager = manager
        super.init()
    }

    func windowWillClose(_ notification: Notification) {
        manager?.windowWillClose()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return true
    }
}
