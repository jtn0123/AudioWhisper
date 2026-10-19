import Foundation

extension RebuildSession {
    func persistInBackground(
        _ result: TranscriptionResult, config: TranscriptionPipelineConfig, duration: TimeInterval?
    ) -> (UUID, Task<String?, Never>)? {
        guard !isPractice else { return nil }
        let token = UUID()
        let task = Task { @MainActor [services] () -> String? in
            do {
                if let save = services.saveResult {
                    try await save(result, config, duration)
                } else {
                    try await services.save(result.text, config, duration)
                }
                return nil
            } catch {
                return "Copied your transcript, but history could not be saved: \(error.localizedDescription)"
            }
        }
        historyTasks[token] = task
        pendingHistoryWrites = historyTasks.count
        return (token, task)
    }

    func waitForHistoryWrites() async {
        while !historyTasks.isEmpty {
            for task in Array(historyTasks.values) { _ = await task.value }
            await Task.yield()
        }
    }

    func selectionChanged() {
        readiness.checking = true
        verificationMessage = nil
        Task { await refreshSetup() }
    }

    func retry() {
        guard hasRetryAudio, let audio = retryAudio else { return }
        guard retryBlockedReason == nil else {
            notice = retryBlockedReason
            return
        }
        sessionID = UUID()
        timing = RebuildSessionTiming()
        deliveryStatus = .none
        notice = nil
        duration = audio.duration
        guard let id = sessionID else { return }
        if let mode = effectiveMode, mode.origin == .appRule {
            phase = .starting
            job = Task { [weak self] in
                guard let self, await checkResolvedMode(mode, id: id) else { return }
                retryAudio = nil
                transcribe(url: audio.url, config: audio.config, id: id, removeAfterward: audio.owned)
            }
            return
        }
        retryAudio = nil
        transcribe(url: audio.url, config: audio.config, id: id, removeAfterward: audio.owned)
    }

    func discardRetry() {
        if let audio = retryAudio, audio.owned { try? FileManager.default.removeItem(at: audio.url) }
        retryAudio = nil
    }

    /// What Smart Paste borrowed from the clipboard, to give back afterwards.
    struct ClipboardLoan {
        let id = UUID()
        let keeper: ClipboardKeeper
        let saved: ClipboardKeeper.Snapshot
    }

    var shouldPasteTranscript: Bool {
        AppDefaults.enableSmartPaste && !(contextRequested && configuration?.writing.contextSource == .selectedText)
    }

    /// Lend the clipboard only when a paste will happen.
    func copyTranscript(_ text: String) -> ClipboardLoan? {
        guard shouldPasteTranscript, capturedTarget != nil, let keeper = services.clipboardKeeper() else {
            services.copy(text)
            return nil
        }
        let loan = ClipboardLoan(keeper: keeper, saved: keeper.save())
        keeper.copy(text, loan: loan.id)
        return loan
    }

    func pasteTranscript(_ text: String, sessionID id: UUID, loan: ClipboardLoan?) async {
        guard shouldPasteTranscript, let target = capturedTarget else {
            timing.delivered = ProcessInfo.processInfo.systemUptime
            timing.delivery = "Copied to clipboard"
            deliveryStatus = .copied
            return
        }
        let copy: (String) -> Void = loan.map { loan in { loan.keeper.copy($0, loan: loan.id) } } ?? services.copy
        let outcome = await delivery.deliver(text, to: target, paste: paste, copy: copy) { [weak self] in
            self?.sessionID == id
        }
        if sessionID == id, !Task.isCancelled {
            timing.delivered = ProcessInfo.processInfo.systemUptime
            switch outcome {
            case .confirmed: timing.delivery = "Paste confirmed"
            case .unverified: timing.delivery = "Paste sent; confirmation unavailable"
            case .failed, .cancelled: timing.delivery = "Copied; paste manually"
            }
        }
        let restored: Bool
        if let loan { restored = await giveBack(loan, after: outcome) } else { restored = false }
        guard !Task.isCancelled, sessionID == id else { return }
        switch outcome {
        case .confirmed: deliveryStatus = .pasted(clipboardRestored: restored)
        case .unverified: deliveryStatus = .unverified(clipboardRestored: restored)
        case .failed, .cancelled: deliveryStatus = .manual
        }
        if outcome == .failed { notice = "Copied. Paste manually with Command V." }
    }

    /// A failed or abandoned paste keeps the transcript for pasting by hand.
    /// One that could not be seen landing gets a moment to be read first.
    func giveBack(_ loan: ClipboardLoan, after outcome: RebuildPasteDelivery.Outcome) async -> Bool {
        switch outcome {
        case .confirmed: break
        case .unverified:
            do { try await delivery.waitBeforeRestore(delivery.restoreGrace) } catch { return false }
        case .failed, .cancelled: return false
        }
        return loan.keeper.restore(loan.saved, loan: loan.id)
    }

}

extension RebuildSession {
    /// When the active recording began, for elapsed-time display. `phase` is
    /// observed, so views re-read this whenever recording starts or stops.
    var recordingStartedAt: Date? { phase == .recording ? startedAt : nil }

    var canUseOriginal: Bool {
        !phase.isBusy && originalTranscript != nil && originalTranscript != transcript
    }

    func useOriginalTranscript() {
        guard canUseOriginal, let originalTranscript else { return }
        transcript = originalTranscript
        services.copy(originalTranscript)
        notice = "Original copied. Paste manually with Command V."
    }
}
