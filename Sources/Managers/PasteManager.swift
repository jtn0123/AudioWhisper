import Foundation
import AppKit
import Carbon
import Observation
import os.log

/// Thread-safe flag to ensure continuation is resumed exactly once.
/// Used to prevent double-resume when timeout and completion race.
internal final class ResumedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _resumed = false

    /// Attempts to resume. Returns true if this is the first call, false otherwise.
    func tryResume() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if _resumed { return false }
        _resumed = true
        return true
    }
}

/// Errors that can occur during paste operations
internal enum PasteError: LocalizedError {
    case accessibilityPermissionDenied
    case eventSourceCreationFailed
    case keyboardEventCreationFailed
    case targetAppNotAvailable

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required for SmartPaste. "
                + "Please enable it in System Settings > Privacy & Security > Accessibility."
        case .eventSourceCreationFailed:
            return "Could not create event source for paste operation."
        case .keyboardEventCreationFailed:
            return "Could not create keyboard events for paste operation."
        case .targetAppNotAvailable:
            return "Target application is not available for pasting."
        }
    }
}

@Observable
@MainActor
internal class PasteManager {

    private let accessibilityManager: AccessibilityPermissionManager
    private let foregroundPID: () -> pid_t?
    private let pasteEvent: (() throws -> Void)?

    init(
        accessibilityManager: AccessibilityPermissionManager = AccessibilityPermissionManager(),
        foregroundPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        pasteEvent: (() throws -> Void)? = nil
    ) {
        self.accessibilityManager = accessibilityManager
        self.foregroundPID = foregroundPID
        self.pasteEvent = pasteEvent
    }

    // MARK: - Clipboard Operations

    /// Copies text to the system clipboard.
    /// This is the centralized method for all clipboard write operations.
    /// - Parameter text: The text to copy to the clipboard.
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Paste Operations

    /// Performs paste with completion handler for proper coordination.
    /// Includes a timeout to prevent indefinite hangs if the completion is never called.
    @MainActor
    func pasteWithCompletionHandler(
        expectedTargetPID: pid_t? = nil,
        isSessionValid: @escaping () -> Bool = { true }
    ) async {
        Logger.paste.debug("pasteWithCompletionHandler called")

        // Use a thread-safe flag to ensure continuation is resumed exactly once
        let resumedFlag = ResumedFlag()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Set up a timeout to prevent indefinite hangs
            // The paste operation should complete almost instantly, so 2 seconds is generous
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(2))
                if resumedFlag.tryResume() {
                    Logger.paste.warning("pasteWithCompletionHandler: timed out waiting for paste completion")
                    continuation.resume()
                }
            }

            pasteWithUserInteraction(expectedTargetPID: expectedTargetPID, isSessionValid: isSessionValid) { result in
                timeoutTask.cancel()
                switch result {
                case .success:
                    Logger.paste.debug("pasteWithCompletionHandler: paste succeeded")
                case .failure(let error):
                    Logger.paste.error("pasteWithCompletionHandler: paste failed: \(error.localizedDescription, privacy: .public)")
                }
                if resumedFlag.tryResume() {
                    continuation.resume()
                }
            }
        }
    }

    /// Performs paste with immediate user interaction context
    /// This should work better than automatic pasting
    func pasteWithUserInteraction(
        expectedTargetPID: pid_t? = nil,
        isSessionValid: @escaping () -> Bool = { true },
        completion: ((Result<Void, PasteError>) -> Void)? = nil
    ) {
        Logger.paste.debug("pasteWithUserInteraction called")
        // Check permission first - if denied, fail gracefully
        // Text is already in clipboard so user can paste manually
        // Don't open System Settings here - it's disruptive and loses focus
        let hasPermission = accessibilityManager.checkPermission()
        Logger.paste.debug("pasteWithUserInteraction: accessibility permission = \(hasPermission)")
        guard hasPermission else {
            Logger.paste.warning("pasteWithUserInteraction: accessibility permission denied")
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return
        }

        // Permission is available - proceed with paste
        Logger.paste.debug("pasteWithUserInteraction: calling performCGEventPaste")
        performCGEventPaste(expectedTargetPID: expectedTargetPID, isSessionValid: isSessionValid, completion: completion)
    }

    // MARK: - CGEvent Paste

    private func performCGEventPaste(
        expectedTargetPID: pid_t?,
        isSessionValid: () -> Bool,
        completion: ((Result<Void, PasteError>) -> Void)? = nil
    ) {
        Logger.paste.debug("performCGEventPaste called")
        // CRITICAL: Prevent any paste operations during tests
        if AppEnvironment.isRunningTests && pasteEvent == nil {
            Logger.paste.debug("performCGEventPaste: skipping in test environment")
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return
        }

        // CRITICAL SECURITY CHECK: Always verify accessibility permission before any CGEvent operations
        // This method should NEVER execute without proper permission - no exceptions
        guard accessibilityManager.checkPermission() else {
            // Permission is not granted - STOP IMMEDIATELY and report error
            // We must never attempt CGEvent operations without permission
            Logger.paste.warning("performCGEventPaste: accessibility permission check failed")
            handlePasteResult(.failure(PasteError.accessibilityPermissionDenied))
            completion?(.failure(PasteError.accessibilityPermissionDenied))
            return
        }

        // Permission is verified - proceed with paste operation
        Logger.paste.debug("performCGEventPaste: calling simulateCmdVPaste")
        do {
            guard let expectedTargetPID, isSessionValid(), foregroundPID() == expectedTargetPID else {
                throw PasteError.targetAppNotAvailable
            }
            if let pasteEvent {
                try pasteEvent()
            } else {
                try simulateCmdVPaste(expectedTargetPID: expectedTargetPID, isSessionValid: isSessionValid)
            }
            // Paste operation completed successfully
            Logger.paste.debug("performCGEventPaste: simulateCmdVPaste succeeded")
            handlePasteResult(.success(()))
            completion?(.success(()))
        } catch let error as PasteError {
            // Handle known paste errors
            Logger.paste.error("performCGEventPaste: PasteError: \(error.localizedDescription, privacy: .public)")
            handlePasteResult(.failure(error))
            completion?(.failure(error))
        } catch {
            // Handle unexpected errors during paste operation
            Logger.paste.error("performCGEventPaste: unexpected error: \(error.localizedDescription, privacy: .public)")
            handlePasteResult(.failure(PasteError.keyboardEventCreationFailed))
            completion?(.failure(PasteError.keyboardEventCreationFailed))
        }
    }

    // Removed - using AccessibilityPermissionManager instead

    private func simulateCmdVPaste(expectedTargetPID: pid_t, isSessionValid: () -> Bool) throws {
        // CRITICAL: Prevent any paste operations during tests
        if AppEnvironment.isRunningTests {
            throw PasteError.accessibilityPermissionDenied
        }

        // Final permission check before creating any CGEvents
        // This is our last line of defense against unauthorized paste operations
        guard accessibilityManager.checkPermission() else {
            throw PasteError.accessibilityPermissionDenied
        }

        // Create event source with proper session state
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            throw PasteError.eventSourceCreationFailed
        }

        // Configure event source to suppress local events during paste operation
        // This prevents interference from local keyboard input
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // Create ⌘V key events for paste operation
        let cmdFlag = CGEventFlags([.maskCommand])
        let vKeyCode = CGKeyCode(kVK_ANSI_V) // V key code

        // Create both key down and key up events for complete key press simulation
        guard let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            throw PasteError.keyboardEventCreationFailed
        }

        // Apply Command modifier flag to both events
        keyVDown.flags = cmdFlag
        keyVUp.flags = cmdFlag

        guard isSessionValid(), foregroundPID() == expectedTargetPID else {
            throw PasteError.targetAppNotAvailable
        }
        // Post the key events to the system
        // This simulates pressing and releasing ⌘V
        keyVDown.post(tap: .cgSessionEventTap)
        keyVUp.post(tap: .cgSessionEventTap)
    }

    private func handlePasteResult(_ result: Result<Void, PasteError>) {
        let (name, object): (Notification.Name, Any?) = {
            switch result {
            case .success: return (.pasteOperationSucceeded, nil)
            case .failure(let error): return (.pasteOperationFailed, error.localizedDescription)
            }
        }()
        NotificationCenter.default.post(name: name, object: object)
    }
}
