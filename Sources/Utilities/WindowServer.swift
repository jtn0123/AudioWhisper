import CoreGraphics
import Foundation

/// Whether this process has a connection to the macOS WindowServer.
///
/// Global hotkey registration goes through Carbon, which reaches CoreGraphics'
/// window server connection. In a process with no GUI session that does not
/// fail gracefully — it aborts the whole process:
///
///     Assertion failed: (CGAtomicGet(&is_initialized)),
///     function CGSConnectionByID, file CGSConnection.mm, line 424.
///
/// GitHub-hosted macOS runners have no GUI session, so every parallel test
/// worker that constructed a `HotKeyManager` died on this — 42 aborted workers
/// per CI run, which no developer ever saw because their machine is logged in.
///
/// The app itself always runs in a GUI session, so this is `true` in
/// production; it exists so a headless process degrades to "hotkeys don't
/// register" instead of SIGABRT.
internal enum WindowServer {
    static var isAvailable: Bool {
        CGSessionCopyCurrentDictionary() != nil
    }
}
