import AppKit
import os.log

// Paste support + notification observers extracted from RecordingViewModel to
// keep the core type body within SwiftLint's type_body_length limit.
@MainActor
extension RecordingViewModel {
    // MARK: - Status Updates

    func updateStatus(
        isRecording: Bool,
        hasPermission: Bool
    ) {
        statusViewModel.updateStatus(
            isRecording: isRecording,
            isProcessing: isProcessing,
            progressMessage: progressMessage,
            hasPermission: hasPermission,
            showSuccess: showSuccess,
            errorMessage: showError ? errorMessage : nil
        )
    }

    // MARK: - Source App Info

    func capturePasteTarget() {
        let foreground = NSWorkspace.shared.frontmostApplication
        let target = foreground?.bundleIdentifier != Bundle.main.bundleIdentifier
            ? foreground : WindowController.storedTargetApp
        hasCapturedPasteTarget = true
        targetAppForPaste = target?.isTerminated == false ? target : nil
        lastSourceAppInfo = targetAppForPaste.flatMap { SourceAppInfo.from(app: $0) } ?? .unknown
    }

    func acceptProgress(_ notification: Notification) -> Bool {
        guard isProcessing else { return false }
        return (notification.userInfo?["sessionID"] as? UUID) == sessionID
    }

    func currentSourceAppInfo() -> SourceAppInfo {
        if let cached = lastSourceAppInfo {
            return cached
        }

        if let stored = WindowController.storedTargetApp,
           let info = SourceAppInfo.from(app: stored) {
            lastSourceAppInfo = info
            return info
        }

        if let app = targetAppForPaste,
           let info = SourceAppInfo.from(app: app) {
            lastSourceAppInfo = info
            return info
        }

        return SourceAppInfo.unknown
    }

    // MARK: - Paste Support

    func performUserTriggeredPaste() {
        Logger.paste.debug("performUserTriggeredPaste called")
        guard let targetApp = findValidTargetApp() else {
            Logger.paste.warning("No valid target app found for paste")
            showSuccess = false
            hideRecordingWindow()
            return
        }

        Logger.paste.debug("Target app found: \(targetApp.localizedName ?? "unknown", privacy: .public)")
        let id = sessionID
        Task { @MainActor [weak self] in
            guard let self, self.isCurrentSession(id) else { return }
            self.hideRecordingWindow()
            await self.activateTargetAppAndPaste(targetApp, sessionID: id)
        }
    }

    /// Resolves the app a paste should land in.
    ///
    /// The step-by-step logging is deliberate and was carried over from the
    /// duplicate that used to live in `ContentView+Paste` (audit item J1).
    /// Smart Paste breaks whenever macOS invalidates Accessibility permission
    /// after a re-sign, and "which app did it think it was pasting into" is the
    /// first question every such report needs answered. Losing it in the
    /// de-duplication would have made the survivor worse than what it replaced.
    func findValidTargetApp() -> NSRunningApplication? {
        let target = hasCapturedPasteTarget ? targetAppForPaste
            : (targetAppForPaste ?? WindowController.storedTargetApp)
        guard let target, !target.isTerminated,
              target.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return target
    }

    /// An unknown destination always means clipboard-only delivery.
    func findFallbackTargetApp() -> NSRunningApplication? { nil }

    /// Fades out the recording window, if there is one. Only that window: this
    /// used to fall back to `NSApp.keyWindow`, which after a paste was
    /// usually the Dashboard, so pasting could make the Dashboard vanish.
    private func hideRecordingWindow() {
        if let window = NSApp?.windows.first(where: { $0.title == WindowTitles.recording }) {
            fadeOutWindow(window)
        }
    }

    func fadeOutWindow(_ window: NSWindow, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        // Retain window during animation to prevent deallocation
        let retainedWindow = window
        let id = sessionID
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            retainedWindow.animator().alphaValue = 0.0
        }, completionHandler: {
            guard self.isCurrentSession(id) else {
                retainedWindow.alphaValue = 1.0
                return
            }
            // Check window is still valid before operating on it
            guard retainedWindow.isVisible || retainedWindow.alphaValue == 0 else {
                completion?()
                return
            }
            retainedWindow.orderOut(nil)
            retainedWindow.alphaValue = 1.0
            completion?()
        })
    }

    private func activateTargetAppAndPaste(_ target: NSRunningApplication, sessionID: UUID) async {
        guard isCurrentSession(sessionID), !target.isTerminated, target.activate(options: []) else {
            if isCurrentSession(sessionID) { showSuccess = false }
            return
        }
        // Activation can cross a Space asynchronously. A timeout leaves the text
        // on the clipboard rather than treating an unrelated foreground app as success.
        let deadline = ContinuousClock.now + .milliseconds(500)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            guard isCurrentSession(sessionID), !target.isTerminated, ContinuousClock.now < deadline else {
                if isCurrentSession(sessionID) { showSuccess = false }
                return
            }
            do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
        }
        guard isCurrentSession(sessionID) else { return }
        await pasteManager.pasteWithCompletionHandler(expectedTargetPID: target.processIdentifier) { [weak self] in
            self?.isCurrentSession(sessionID) == true
        }
        if isCurrentSession(sessionID) { showSuccess = false }
    }

    // MARK: - Notification Observers

    func setupNotificationObservers() {
        stopNotificationObservers()

        // Transcription progress
        let progressTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .transcriptionProgress) {
                if self?.acceptProgress(notification) == true,
                   let message = notification.object as? String {
                    self?.progressMessage = message
                }
            }
        }
        notificationTasks.append(progressTask)

        // Target app stored
        let targetAppTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .targetAppStored) {
                if self?.isProcessing == false, self?.capturedRecordingSettings == nil,
                   let app = notification.object as? NSRunningApplication {
                    self?.targetAppForPaste = app
                    if let info = SourceAppInfo.from(app: app) {
                        self?.lastSourceAppInfo = info
                    }
                }
            }
        }
        notificationTasks.append(targetAppTask)

        // Recording failed
        let recordingFailedTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .recordingStartFailed) {
                self?.errorMessage = LocalizedStrings.Errors.failedToStartRecording
                self?.showError = true
            }
        }
        notificationTasks.append(recordingFailedTask)
    }

    func stopNotificationObservers() {
        for task in notificationTasks {
            task.cancel()
        }
        notificationTasks.removeAll()
    }
}

