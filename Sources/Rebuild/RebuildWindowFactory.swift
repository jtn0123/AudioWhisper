import AppKit
import SwiftUI

/// Construct the actual native windows without activating or presenting them.
/// The delegate owns their lifetimes and standard-window presentation policy.
@MainActor
enum RebuildWindowFactory {
    static func workspace(root: RebuildRootView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AudioWhisper Rebuild"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 870, height: 620)
        window.contentViewController = RebuildWorkspaceHosting.controller(for: root)
        return window
    }

    static func recorder(session: RebuildSession, recorder: AudioEngineRecorder) -> NSWindow {
        let window = ChromelessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 230),
            styleMask: [.borderless], backing: .buffered, defer: false)
        RecordingWindowStyle.configure(window)
        let controller = NSHostingController(rootView: RebuildRecorderView(session: session, recorder: recorder))
        // The recorder has a fixed native frame. SwiftUI's initial intrinsic
        // size can be zero before its first layout; it must not resize the panel.
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 380, height: 230))
        return window
    }
}
