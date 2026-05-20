import Foundation
import AppKit

internal class KeyboardEventHandler {
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private let isTestEnvironment: Bool
    
    init(isTestEnvironment: Bool = AppEnvironment.isRunningTests) {
        self.isTestEnvironment = isTestEnvironment
        
        // Avoid installing global monitors in tests to prevent flaky AppKit interactions
        if !isTestEnvironment {
            setupGlobalKeyMonitoring()
        }
    }
    
    private func setupGlobalKeyMonitoring() {
        // Use global monitor that works regardless of focus.
        // `[weak self]` prevents the monitor closure from retaining the handler;
        // without it `deinit` never fires and the monitor leaks (bug H10).
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            // Check if recording window is visible
            if let window = NSApp.windows.first(where: { $0.title == WindowTitles.recording }), window.isVisible {
                _ = self.handleKeyEvent(event, for: window)
            }
        }

        // Also add local monitor with proper filtering.
        // `[weak self]` here too — same reason as the global monitor above.
        // Note: local monitor closure must return `NSEvent?`, so the early
        // exit returns `event` (pass through) rather than `nil`.
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Check if recording window is visible
            if let window = NSApp.windows.first(where: { $0.title == WindowTitles.recording }), window.isVisible {
                // Always consume events when recording window is visible to prevent passthrough
                _ = self.handleKeyEvent(event, for: window)
                return nil // Consume the event to prevent it from reaching other apps
            }
            return event
        }
    }
    
    @discardableResult
    func handleKeyEvent(_ event: NSEvent, for window: NSWindow) -> NSEvent? {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let modifiers = event.modifierFlags
        
        // Handle space key
        if key == " " && !modifiers.contains(.command) {
            NotificationCenter.default.post(name: .spaceKeyPressed, object: nil)
            return nil // Consume the event
        }
        
        // Handle escape key
        if key == String(Character(UnicodeScalar(27)!)) { // Escape
            NotificationCenter.default.post(name: .escapeKeyPressed, object: nil)
            return nil // Consume the event
        }
        
        // Handle return key
        if key == String(Character(UnicodeScalar(13)!)) || key == "\r" { // Return/Enter
            NotificationCenter.default.post(name: .returnKeyPressed, object: nil)
            return nil // Consume the event
        }
        
        // Allow ⌘, for opening dashboard/settings replacement
        if key == "," && modifiers.contains(.command) {
            Task { @MainActor in
                DashboardWindowManager.shared.showDashboardWindow()
            }
            return nil // Consume the event
        }
        
        // Block all other keyboard shortcuts when recording window is focused
        if modifiers.contains(.command) {
            return nil // Consume and block the event
        }
        
        // Allow non-command keys to pass through
        return event
    }
    
    deinit {
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
        
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }
}
