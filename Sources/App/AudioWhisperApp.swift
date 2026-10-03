import AppKit
import SwiftUI

@main
internal struct AudioWhisperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // A menu bar app: AppDelegate creates every window, and the status
        // item, itself. SwiftUI still needs one scene, so this is a menu bar
        // extra that is never inserted — a scene with no window to open.
        //
        // It was a `WindowGroup` of `EmptyView()`, which opened a zero-size
        // window at launch, hid it by hiding `NSApplication.shared.windows.first`
        // — whichever window that happened to be — and added a File ▸ New
        // Window item that made more of them. An empty `Settings` scene is no
        // better: SwiftUI opens it, blank, whenever the app is reopened.
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
            // There is no help book, so the default item only says
            // "Help isn't available for AudioWhisper".
            CommandGroup(replacing: .help) {
                Button("AudioWhisper Help") {
                    WelcomeWindow.show()
                }
            }
        }
    }
}
