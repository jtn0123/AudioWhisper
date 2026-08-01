import CoreGraphics
import Foundation

/// Environment probes for code that cannot run without a WindowServer.
///
/// Global hotkey registration goes through Carbon, which reaches CoreGraphics'
/// window server connection. In a process without one that does not fail
/// gracefully — it aborts the whole process:
///
///     Assertion failed: (CGAtomicGet(&is_initialized)),
///     function CGSConnectionByID, file CGSConnection.mm, line 424.
///
/// GitHub-hosted macOS runners hit exactly this: every parallel test worker
/// that constructed a `HotKeyManager` died, 42 aborted workers per run. No
/// developer machine reproduces it.
internal enum WindowServer {
    /// True only in a test process — XCTest is never loaded in the shipping app.
    static var isRunningUnderTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    /// Whether to register real, system-wide hotkeys.
    ///
    /// This is gated on the test process and NOTHING else, deliberately. The
    /// obvious alternative — probe for a usable WindowServer and skip
    /// registration when there isn't one — was tried and rejected: every probe
    /// available here (`CGSessionCopyCurrentDictionary`, active display count)
    /// either returns a false positive on a CI runner or a false negative on a
    /// real Mac whose displays are asleep or closed. Wiring the app's core
    /// feature to a probe that reports "no display" during clamshell mode would
    /// trade a CI annoyance for silently dead hotkeys on a user's machine.
    ///
    /// Suppressing registration under test is safe and independently worth
    /// doing: a suite that registers global hotkeys takes over the user's real
    /// key combination (⌘⇧Space by default) for the length of the run. No test
    /// asserts on registered-shortcut state, so nothing is lost.
    static var canRegisterGlobalHotkeys: Bool {
        !isRunningUnderTests
    }

    /// At least one active display, i.e. AppKit UI that needs a real window
    /// (`NSStatusItem`) can be created.
    ///
    /// **Test-only.** Production must not branch on this — see the note above.
    static var hasActiveDisplay: Bool {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else { return false }
        return displayCount > 0
    }
}
