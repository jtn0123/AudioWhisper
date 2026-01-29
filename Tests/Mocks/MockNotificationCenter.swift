import Foundation
@testable import AudioWhisper

/// Mock NotificationCenter for capturing and verifying posted notifications
final class MockNotificationCenter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MockNotificationCenter", attributes: .concurrent)
    private var _postedNotifications: [(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?)] = []

    var postedNotifications: [(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?)] {
        queue.sync { _postedNotifications }
    }

    func post(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        queue.async(flags: .barrier) {
            self._postedNotifications.append((name: name, object: object, userInfo: userInfo))
        }
    }

    func post(_ notification: Notification) {
        queue.async(flags: .barrier) {
            self._postedNotifications.append((name: notification.name, object: notification.object, userInfo: notification.userInfo))
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

    /// Get all notifications with the given name
    func notifications(for name: Notification.Name) -> [(name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?)] {
        queue.sync {
            _postedNotifications.filter { $0.name == name }
        }
    }

    /// Get the last notification with the given name
    func lastNotification(for name: Notification.Name) -> (name: Notification.Name, object: Any?, userInfo: [AnyHashable: Any]?)? {
        queue.sync {
            _postedNotifications.last { $0.name == name }
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
