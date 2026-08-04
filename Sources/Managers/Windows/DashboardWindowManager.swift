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

    /// How many records the cache holds. The status menu's "Recent" section
    /// asks for 3 (`AppDelegate+Menu`); 10 leaves room without paying for it.
    private static let recentCacheSize = 10

    /// Reloads the recent-records cache from the data layer.
    ///
    /// Fetches only what the cache holds. This used to call
    /// `fetchAllRecordsQuietly()` and then sort the whole history in memory to
    /// take `.prefix(10)` — so opening the menu loaded every transcript ever
    /// recorded to display three of them. `fetchRecords(limit:offset:search:)`
    /// sorts by date descending in the store and applies `fetchLimit`, so the
    /// work is bounded by `recentCacheSize` rather than by history size.
    func refreshRecentRecordsCache() async {
        // `?? []` preserves the previous failure behaviour: the old
        // `...Quietly` call swallowed errors and yielded an empty list.
        recentRecordsCache = (try? await DataManager.shared.fetchRecords(
            limit: Self.recentCacheSize,
            offset: 0,
            search: nil
        )) ?? []
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
