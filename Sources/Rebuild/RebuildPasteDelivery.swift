// swiftlint:disable:next unused_import - verified required: removing it breaks the build (pid_t)
import Foundation

/// Delivers a transcript into the captured app and confirms that it arrived.
///
/// A synthetic ⌘V is fire-and-forget: a field that lost focus, a sheet, or an
/// app that ignores synthetic keys swallows it and nothing tells the user.
/// When Accessibility can read the focused text control, delivery watches it
/// — by polling and through change notifications — for the change a paste
/// makes and, if none comes, presses the app's own Edit ▸ Paste once. When the
/// control is unreadable the ⌘V is trusted, as it always was: text is never
/// pasted twice on a guess.
@MainActor
struct RebuildPasteDelivery {
    enum Outcome: Equatable {
        case confirmed, unverified, failed, cancelled
    }

    var focusedText: FocusedTextAccess = .live
    /// Long enough for a busy app to apply the paste before the fallback could
    /// double it, short enough that a failure is reported promptly.
    var confirmationWindow: Duration = .milliseconds(800)
    var pollInterval: Duration = .milliseconds(40)
    /// How long a paste that could not be confirmed may still be reading the
    /// clipboard before the user's own contents go back on it.
    var restoreGrace: Duration = .seconds(1)
    /// Read at delivery time, so the Preferences toggle applies to the next paste.
    var matchContext: () -> Bool = { AppDefaults.matchCursorContext }

    func deliver(
        _ text: String, to target: RebuildPasteDestination, paste: PasteManager, copy: (String) -> Void,
        isValid: @escaping () -> Bool
    ) async -> Outcome {
        let activated = await target.activateAndWait(isSessionValid: isValid)
        guard !Task.isCancelled, isValid() else { return .cancelled }
        guard activated else { return .failed }
        let pid = target.processIdentifier
        let deliveryValid = { !Task.isCancelled && isValid() && !target.isTerminated() && target.foregroundPID() == pid }
        let before = focusedText.read(pid)
        let changes = before == nil ? nil : focusedText.watchChanges(pid)
        defer { changes?.stop() }
        if matchContext(), let preceding = before?.preceding {
            let fitted = CursorContextFormatter.fit(text, after: preceding)
            if fitted != text { copy(fitted) }
        }
        var pasted = false
        paste.pasteWithUserInteraction(expectedTargetPID: pid, isSessionValid: deliveryValid) { result in
            if case .success = result { pasted = true }
        }
        guard deliveryValid() else { return .cancelled }
        guard pasted else { return .failed }
        return await confirm(pid: pid, before: before, changes: changes, isValid: deliveryValid)
    }

    func confirm(
        pid: pid_t, before: FocusedTextState?, changes: FocusedTextChanges?, isValid: () -> Bool
    ) async -> Outcome {
        guard let before else { return .unverified }
        // Counted from the watcher's start: a notification may land before
        // the first poll, even before the shortcut call returns.
        switch await observeChange(pid, from: before, changes: changes, since: 0, isValid: isValid) {
        case .changed: return .confirmed
        case .unknown: return isValid() ? .unverified : .cancelled
        case .unchanged:
            guard isValid() else { return .cancelled }
            let baseline = changes?.count() ?? 0
            guard focusedText.pressPasteMenuItem(pid) else { return .failed }
            switch await observeChange(pid, from: before, changes: changes, since: baseline, isValid: isValid) {
            case .changed: return .confirmed
            case .unknown: return isValid() ? .unverified : .cancelled
            case .unchanged: return .failed
            }
        }
    }

    private enum Observation { case changed, unchanged, unknown }

    /// A control that stops being readable (focus moved, the app went away)
    /// is `unknown`, never `unchanged`: only a field seen to stay the same,
    /// with no change notification either, justifies pasting again.
    private func observeChange(
        _ pid: pid_t, from before: FocusedTextState, changes: FocusedTextChanges?, since baseline: Int,
        isValid: () -> Bool
    ) async -> Observation {
        let deadline = ContinuousClock.now + confirmationWindow
        repeat {
            guard !Task.isCancelled, isValid() else { return .unknown }
            if let changes, changes.count() > baseline { return .changed }
            guard let now = focusedText.read(pid) else { return .unknown }
            if let identity = before.controlIdentity, now.controlIdentity != identity { return .unknown }
            if now.length != before.length || now.selection != before.selection { return .changed }
            do { try await Task.sleep(for: pollInterval) } catch { return .unknown }
        } while ContinuousClock.now < deadline
        return .unchanged
    }
}
