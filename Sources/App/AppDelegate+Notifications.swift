import AppKit

internal extension AppDelegate {
    func setupNotificationObservers() {
        // Note: These observers are automatically cleaned up when the app terminates.
        // AppDelegate lives for the entire app lifecycle, so no explicit removal needed,
        // but we use the block-based API for clarity and to avoid selector-based pitfalls.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showDashboard),
            name: .welcomeCompleted,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(restoreFocusToPreviousApp),
            name: .restoreFocusToPreviousApp,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onRecordingStopped),
            name: .recordingStopped,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPressAndHoldSettingsChanged(_:)),
            name: .pressAndHoldSettingsChanged,
            object: nil
        )
    }

    @objc private func onPressAndHoldSettingsChanged(_ notification: Notification) {
        configureShortcutMonitors()
    }
}
