import Foundation
import AppKit
@testable import AudioWhisper

/// Mock WindowController for testing window operations without actual UI
@MainActor
final class MockWindowController {
    // MARK: - Call Tracking

    var toggleRecordWindowCalled = false
    var toggleRecordWindowCallCount = 0
    var lastToggleWindow: NSWindow?
    var toggleRecordWindowCompletionCalled = false

    var openSettingsCalled = false
    var openSettingsCallCount = 0

    var restoreFocusToPreviousAppCalled = false
    var restoreFocusCallCount = 0
    var restoreFocusCompletionCalled = false

    // MARK: - Behavior Configuration

    var shouldCallCompletion = true

    // MARK: - Methods

    func toggleRecordWindow(_ window: NSWindow? = nil, completion: (() -> Void)? = nil) {
        toggleRecordWindowCalled = true
        toggleRecordWindowCallCount += 1
        lastToggleWindow = window

        if shouldCallCompletion {
            toggleRecordWindowCompletionCalled = true
            completion?()
        }
    }

    func openSettings() {
        openSettingsCalled = true
        openSettingsCallCount += 1
    }

    func restoreFocusToPreviousApp(completion: (() -> Void)? = nil) {
        restoreFocusToPreviousAppCalled = true
        restoreFocusCallCount += 1

        if shouldCallCompletion {
            restoreFocusCompletionCalled = true
            completion?()
        }
    }

    // MARK: - Test Helpers

    func reset() {
        toggleRecordWindowCalled = false
        toggleRecordWindowCallCount = 0
        lastToggleWindow = nil
        toggleRecordWindowCompletionCalled = false

        openSettingsCalled = false
        openSettingsCallCount = 0

        restoreFocusToPreviousAppCalled = false
        restoreFocusCallCount = 0
        restoreFocusCompletionCalled = false

        shouldCallCompletion = true
    }
}
