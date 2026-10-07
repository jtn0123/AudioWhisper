import Foundation
// swiftlint:disable:next unused_import - verified required: removing it breaks the build
@testable import AudioWhisper

/// A single notification captured by `MockNotificationCenter`.
struct CapturedNotification {
    let name: Notification.Name
    let object: Any?
    let userInfo: [AnyHashable: Any]?
}

/// Mock NotificationCenter for capturing and verifying posted notifications
final class MockNotificationCenter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MockNotificationCenter", attributes: .concurrent)
    private var _postedNotifications: [CapturedNotification] = []

    func post(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        queue.async(flags: .barrier) {
            self._postedNotifications.append(
                CapturedNotification(name: name, object: object, userInfo: userInfo)
            )
        }
    }

    // MARK: - Assertion Helpers

    /// Check if a notification with the given name was posted
    func didPost(_ name: Notification.Name) -> Bool {
        queue.sync {
            _postedNotifications.contains { $0.name == name }
        }
    }

    /// Get the count of notifications with the given name
    func postCount(for name: Notification.Name) -> Int {
        queue.sync {
            _postedNotifications.filter { $0.name == name }.count
        }
    }

    /// Clear all posted notifications
    func reset() {
        queue.async(flags: .barrier) {
            self._postedNotifications.removeAll()
        }
    }

    /// Wait for notifications to settle (useful after async operations)
    func waitForNotifications() async {
        try? await Task.sleep(for: .milliseconds(50))
    }
}
