import SwiftUI
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

        if let fallback = findFallbackTargetApp(),
           let info = SourceAppInfo.from(app: fallback) {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.hideRecordingWindow()
            self?.activateTargetAppAndPaste(targetApp)
        }
    }

    func findValidTargetApp() -> NSRunningApplication? {
        var targetApp = WindowController.storedTargetApp

        if targetApp == nil {
            targetApp = targetAppForPaste
        }

        if let stored = targetApp, stored.isTerminated {
            targetApp = nil
        }

        if targetApp == nil {
            targetApp = findFallbackTargetApp()
        }

        return targetApp
    }

    func findFallbackTargetApp() -> NSRunningApplication? {
        let runningApps = NSWorkspace.shared.runningApplications

        return runningApps.first { app in
            app.bundleIdentifier != Bundle.main.bundleIdentifier &&
            app.bundleIdentifier != "com.tinyspeck.slackmacgap" &&
            app.bundleIdentifier != "com.cron.electron" &&
            app.activationPolicy == .regular &&
            !app.isTerminated
        }
    }

    private func hideRecordingWindow() {
        let recordWindow = NSApp.windows.first { $0.title == WindowTitles.recording }
        if let window = recordWindow {
            fadeOutWindow(window)
        } else if let keyWindow = NSApplication.shared.keyWindow {
            fadeOutWindow(keyWindow)
        }
    }

    func fadeOutWindow(_ window: NSWindow, duration: TimeInterval = 0.3, completion: (() -> Void)? = nil) {
        // Retain window during animation to prevent deallocation
        let retainedWindow = window
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            retainedWindow.animator().alphaValue = 0.0
        }, completionHandler: {
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

    private func activateTargetAppAndPaste(_ target: NSRunningApplication) {
        Task { @MainActor in
            do {
                try await activateApplication(target)
                await pasteManager.pasteWithCompletionHandler()
                showSuccess = false
            } catch {
                Logger.paste.error("activateTargetAppAndPaste failed: \(error.localizedDescription)")
                showSuccess = false
            }
        }
    }

    private func activateApplication(_ target: NSRunningApplication) async throws {
        let success = target.activate(options: [])

        if !success {
            if let bundleURL = target.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true

                return try await withCheckedThrowingContinuation { continuation in
                    NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            } else {
                throw NSError(
                    domain: "AudioWhisper",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to activate target application"]
                )
            }
        }

        await waitForApplicationActivation(target)
    }

    private func waitForApplicationActivation(_ target: NSRunningApplication) async {
        if target.isActive { return }

        // Use actor for thread-safe resume coordination
        let coordinator = ActivationCoordinator()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let timeoutTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                let shouldResume = await coordinator.tryResume()
                if shouldResume {
                    continuation.resume()
                }
            }

            let observer = NotificationCenter.default.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { notification in
                if let activatedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   activatedApp.processIdentifier == target.processIdentifier {
                    timeoutTask.cancel()
                    Task {
                        let shouldResume = await coordinator.tryResume()
                        if shouldResume {
                            continuation.resume()
                        }
                    }
                }
            }

            // Clean up observer after a delay
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }

    // MARK: - Notification Observers

    func setupNotificationObservers() {
        stopNotificationObservers()

        // Transcription progress
        let progressTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .transcriptionProgress) {
                if let message = notification.object as? String {
                    self?.progressMessage = message
                }
            }
        }
        notificationTasks.append(progressTask)

        // Target app stored
        let targetAppTask = Task { @MainActor [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .targetAppStored) {
                if let app = notification.object as? NSRunningApplication {
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

// MARK: - Activation Coordinator

/// Actor to safely coordinate single resume of continuation
private actor ActivationCoordinator {
    private var resumed = false

    func tryResume() -> Bool {
        if resumed { return false }
        resumed = true
        return true
    }
}
