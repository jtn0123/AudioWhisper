import AppKit

/// How the recording window sits on screen: above other windows, on every
/// Space including full-screen ones, out of the way of ⌘-` and the Window menu,
/// and on the screen the user is working on.
///
/// This was set in two places — when the window was created and again each
/// time it was shown — which had drifted apart, and both included
/// `.fullScreenPrimary`, which made the borderless overlay itself eligible to
/// go full screen.
internal enum RecordingWindowStyle {
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,     // every Space
        .fullScreenAuxiliary,  // auxiliary to a full-screen window
        .canJoinAllApplications, // eligible over another app's full-screen Space
        .ignoresCycle          // ⌘-` skips it
    ]

    static func configure(_ window: NSWindow) {
        // Floating, not .screenSaver: full-screen visibility comes from
        // .fullScreenAuxiliary, and a higher level interferes with input.
        window.level = .floating
        window.collectionBehavior = collectionBehavior
        window.hidesOnDeactivate = false
        window.canHide = false
        window.isExcludedFromWindowsMenu = true
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isRestorable = false
    }

    /// Moves `window` onto the screen under the pointer, if it is not on it
    /// already. It used to be centred once, on whichever screen was main when
    /// it was created, and so appeared on the wrong display for anyone
    /// working on another one.
    static func moveToActiveScreen(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        window.setFrameOrigin(frameOrigin(for: window.frame, on: visibleFrame))
    }

    /// Where a window with `frame` goes on a screen with `visibleFrame`: where
    /// it is, if it is fully visible — so a window the user dragged stays put —
    /// and centred on it otherwise. Its controls must clear the Dock and edges.
    static func frameOrigin(for frame: NSRect, on visibleFrame: NSRect) -> NSPoint {
        if visibleFrame.contains(frame) {
            return frame.origin
        }
        return NSPoint(
            x: (visibleFrame.midX - frame.width / 2).rounded(),
            y: (visibleFrame.midY - frame.height / 2).rounded()
        )
    }
}
