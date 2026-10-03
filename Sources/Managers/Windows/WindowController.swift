import Foundation
import AppKit
import os.log

/// Manages window display and focus restoration for AudioWhisper
/// 
/// This class handles showing/hiding the recording window and restoring focus
/// to the previous application. All window operations now support optional
/// completion handlers for better coordination and testing.
internal class WindowController {
    private var previousApp: NSRunningApplication?
    private let isTestEnvironment: Bool

    // Thread-safe static property to share target app with ContentView
    private static let storedTargetAppQueue = DispatchQueue(label: "com.audiowhisper.storedTargetApp", attributes: .concurrent)
    private static var _storedTargetApp: NSRunningApplication?

    static var storedTargetApp: NSRunningApplication? {
        get {
            return storedTargetAppQueue.sync {
                return _storedTargetApp
            }
        }
        set {
            storedTargetAppQueue.sync(flags: .barrier) {
                _storedTargetApp = newValue
            }
        }
    }

    init() {
        isTestEnvironment = AppEnvironment.isRunningTests
    }

    func toggleRecordWindow(_ window: NSWindow? = nil, completion: (() -> Void)? = nil) {
        // Don't show recorder window during first-run welcome experience
        let hasCompletedWelcome = AppDefaults.hasCompletedWelcome
        if !hasCompletedWelcome {
            completion?()
            return
        }

        // In test environment, exit early
        if isTestEnvironment {
            completion?()
            return
        }

        // Use provided window or find the recording window by title
        let recordWindow = window ?? NSApp.windows.first { window in
            window.title == WindowTitles.recording
        }

        if let window = recordWindow {
            if window.isVisible {
                hideWindow(window, completion: completion)
            } else {
                showWindow(window, completion: completion)
            }
        } else {
            completion?()
        }
    }

    private func hideWindow(_ window: NSWindow, completion: (() -> Void)? = nil) {
        // Clear the shared target-app reference as the window goes down. The
        // value gets re-stored next time `showWindow` runs, so leaving it set
        // here lets a stale `NSRunningApplication` survive across sessions
        // (bug H22). Defensive even when `restoreFocusToPreviousApp` will
        // also clear it — `hideWindow` is the canonical "session end".
        WindowController.storedTargetApp = nil
        fadeOutWindow(window) { [weak self] in
            self?.restoreFocusToPreviousApp(completion: completion)
        }
    }

    private func fadeOutWindow(_ window: NSWindow, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1.0  // Reset for next show
            completion?()
        })
    }

    private func showWindow(_ window: NSWindow, completion: (() -> Void)? = nil) {
        // Skip actual window operations in test environment
        if isTestEnvironment {
            completion?()
            return
        }

        // Remember the currently active app before showing our window
        storePreviousApp()

        // An overlay on every Space, shown without stealing focus or
        // switching Spaces, on the screen the user is working on.
        RecordingWindowStyle.configure(window)
        RecordingWindowStyle.moveToActiveScreen(window)

        // Show window without activating the app (prevents space switching)
        window.orderFrontRegardless()

        // Small delay then ensure proper focus
        performWindowOperation(after: 0.02) {
            if window.canBecomeKey {
                window.makeKey()
            }
            window.makeFirstResponder(window.contentView)
            completion?()
        }
    }

    /// Helper method to perform window operations with delays and completion handlers
    private func performWindowOperation(after delay: TimeInterval, operation: @escaping () -> Void) {
        Task { @MainActor in
            if delay > 0 {

                try? await Task.sleep(for: .seconds(delay))
            }
            operation()
        }
    }

    private func storePreviousApp() {
        let workspace = NSWorkspace.shared
        Logger.paste.debug("storePreviousApp called")
        if let frontmostApp = workspace.frontmostApplication,
           frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmostApp
            WindowController.storedTargetApp = frontmostApp
            Logger.paste.debug("storePreviousApp: stored \(frontmostApp.localizedName ?? "unknown", privacy: .public)")

            // Also notify via NotificationCenter as backup
            NotificationCenter.default.post(
                name: .targetAppStored,
                object: frontmostApp
            )
        } else {
            Logger.paste.debug("storePreviousApp: no suitable frontmost app found")
        }
    }

    func restoreFocusToPreviousApp(completion: (() -> Void)? = nil) {
        guard let prevApp = previousApp else {
            // Even if `previousApp` is nil, clear the shared static value so
            // a stale entry from a previous session can't leak (bug H22).
            WindowController.storedTargetApp = nil
            completion?()
            return
        }

        // Small delay to ensure window is hidden first
        performWindowOperation(after: 0.1) { [weak self] in
            prevApp.activate(options: [])
            self?.previousApp = nil
            // Clear the shared target-app reference once focus has been
            // restored; otherwise it stays alive across sessions and
            // `findValidTargetApp` may pick the wrong app next time (bug H22).
            WindowController.storedTargetApp = nil
            completion?()
        }
    }

    @MainActor func openSettings() {
        // Skip actual window operations in test environment
        if isTestEnvironment {
            return
        }

        // Hide recording window if open to avoid overlap
        if let recordWindow = NSApp.windows.first(where: { $0.title == WindowTitles.recording }), recordWindow.isVisible {
            recordWindow.orderOut(nil)
        }

        DashboardWindowManager.shared.showDashboardWindow()
    }
}
