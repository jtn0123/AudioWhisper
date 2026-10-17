import SwiftUI

extension View {
    /// Announce status changes, never the timer, waveform or each draft word.
    func rebuildAnnouncement(_ message: String, onAppear: Bool = false) -> some View {
        self.onChange(of: message) { _, value in RebuildAnnouncements.post(value) }
            .onAppear { if onAppear { RebuildAnnouncements.post(message) } }
    }
}

@MainActor
enum RebuildAnnouncements {
    static func post(_ message: String) {
        guard !AppEnvironment.isRunningTests, let application = NSApp else { return }
        NSAccessibility.post(element: application, notification: .announcementRequested, userInfo: [
            .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
    }
}
