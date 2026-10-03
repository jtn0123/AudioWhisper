import SwiftUI

@main
internal struct AudioWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// A menu bar app: AppDelegate creates every window, and the status item,
    /// itself. SwiftUI still needs one scene, so this is a menu bar extra that
    /// is never inserted — a scene with no window to open.
    ///
    /// It was a `WindowGroup` of `EmptyView()`, which opened a zero-size window
    /// at launch, hid it by hiding `NSApplication.shared.windows.first` —
    /// whichever window that happened to be — and added a File ▸ New Window
    /// item that made more of them. An empty `Settings` scene is no better:
    /// SwiftUI opens it, blank, whenever the app is reopened.
    ///
    /// There is no help book, so Help opens the welcome window rather than
    /// saying "Help isn't available for AudioWhisper".
    var body: some Scene {
        MenuBarExtra("AudioWhisper", systemImage: "mic", isInserted: .constant(false)) {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Dashboard...") {
                    DashboardWindowManager.shared.showDashboardWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("AudioWhisper Help") {
                    WelcomeWindow.show()
                }
            }
        }
    }
}
