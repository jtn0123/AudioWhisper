import AppKit

/// What the recorder shows after a dictation ends without delivering text.
///
/// People usually dictate from another app, often full screen, so the
/// workspace window's notice is invisible to them. Without this the recorder
/// simply vanished on failure and nothing arrived. The outcome keeps the
/// recorder on screen briefly with the reason and a way forward.
enum RebuildRecorderOutcome: Equatable {
    /// Dictation failed; the message says why. Retry is offered when the
    /// session kept the audio.
    case failed(String)
    /// Text was transcribed and copied, but Smart Paste could not insert it.
    case pasteManually

    var title: String {
        switch self {
        case .failed: return "Dictation didn't finish"
        case .pasteManually: return "Copied — press ⌘V to paste"
        }
    }

    var message: String {
        switch self {
        case .failed(let message): return message
        case .pasteManually: return "AudioWhisper couldn't paste into the app. Your text is on the clipboard."
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Failures carry more to read than the paste hint.
    var displaySeconds: Double {
        switch self {
        case .failed: return 6
        case .pasteManually: return 4
        }
    }
}

extension RebuildSession {
    /// Ends a failed dictation: records the reason, keeps the recorder visible
    /// long enough to read it, and plays the error sound.
    func presentFailure(_ message: String) {
        notice = message
        phase = .failed
        guard !isPractice else {
            closeRecorder()
            return
        }
        if AppDefaults.playCompletionSound { NSSound(named: "Basso")?.play() }
        presentOutcome(.failed(message))
    }

    func presentOutcome(_ outcome: RebuildRecorderOutcome) {
        recorderOutcome = outcome
        showRecorder()
        scheduleOutcomeDismissal(after: outcome.displaySeconds)
    }

    /// Pauses the countdown while the pointer is over the recorder, so a long
    /// message can be read and its buttons reached.
    func holdOutcome(_ hovering: Bool) {
        guard let outcome = recorderOutcome else { return }
        if hovering {
            outcomeDismissal?.cancel()
            outcomeDismissal = nil
        } else {
            scheduleOutcomeDismissal(after: outcome.displaySeconds / 2)
        }
    }

    func dismissOutcome() {
        outcomeDismissal?.cancel()
        outcomeDismissal = nil
        guard recorderOutcome != nil else { return }
        recorderOutcome = nil
        // A new recording may already own the recorder; leave it open then.
        if !phase.isBusy { closeRecorder() }
    }

    /// Retry keeps the recorder up to show "Transcribing…" for the new attempt.
    func retryFromRecorder() {
        clearOutcome()
        retry()
        if !phase.isBusy, recorderOutcome == nil { closeRecorder() }
    }

    func openWorkspaceFromRecorder() {
        dismissOutcome()
        openWorkspace()
    }

    /// Clears a lingering outcome when a new dictation starts.
    func clearOutcome() {
        outcomeDismissal?.cancel()
        outcomeDismissal = nil
        recorderOutcome = nil
    }

    private func scheduleOutcomeDismissal(after seconds: Double) {
        outcomeDismissal?.cancel()
        let delay = seconds * outcomeTimeScale
        outcomeDismissal = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.dismissOutcome()
        }
    }
}
