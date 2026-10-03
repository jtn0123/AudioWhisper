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

    /// Held strongly from creation until it closes, so a minimised or
    /// background Dashboard is the same window the next request brings back.
    private var dashboardWindow: NSWindow?
    private var windowDelegate: StandardWindowDelegate?
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
    ///
    /// "Existing" includes a minimised Dashboard. This used to check
    /// `isVisible`, which is false for a window in the Dock, so asking for the
    /// Dashboard while it was minimised opened a second one beside it.
    func showDashboardWindow() {
        if isTestEnvironment {
            return
        }

        if let existingWindow = dashboardWindow {
            StandardWindow.present(existingWindow)
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

        window.contentViewController = hostingController
        window.title = "AudioWhisper Dashboard"
        window.setContentSize(initialSize)
        window.minSize = minimumSize

        // Follow system appearance
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden

        StandardWindow.configure(window, frameAutosaveName: "AudioWhisperDashboard")

        windowDelegate = StandardWindowDelegate { [weak self] in
            self?.windowWillClose()
        }
        window.delegate = windowDelegate

        dashboardWindow = window
        StandardWindow.present(window)

        Logger.app.info("Dashboard window created and shown")
    }

    func windowWillClose() {
        dashboardWindow = nil
        windowDelegate = nil
        Logger.app.info("Dashboard window closed and references cleaned up")
    }
}
