import AppKit

/// Presents AudioWhisper as a regular app — Dock icon, ⌘-Tab entry, its own
/// menu bar — while one of its normal windows is open, and as a menu-bar
/// accessory the rest of the time.
///
/// The app used to stay an accessory throughout. An accessory's windows have
/// no Dock icon and no ⌘-Tab entry, so once the Dashboard fell behind another
/// window the menu bar icon was the only way back to it, and minimising it sent
/// it to a Dock tile that "Dashboard" in the menu then ignored, opening a
/// second Dashboard instead. Windows that stay on top regardless (the recording
/// window) are not tracked: they never needed the Dock to be found.
///
/// A regular app's menus cannot open on another app's full-screen Space: the
/// menu bar icon highlights and nothing appears, for any regular app (measured
/// with Unity Hub too). So when the menu bar icon is clicked away from
/// AudioWhisper's windows, it steps aside to an accessory for the menu, and
/// becomes regular again on getting back to one of its windows.
@MainActor
internal final class ActivationPolicyController: NSObject {
    static let shared = ActivationPolicyController(
        workspaceNotifications: NSWorkspace.shared.notificationCenter,
        appNotifications: .default
    )

    /// The policy last applied.
    private(set) var policy: NSApplication.ActivationPolicy = .accessory
    private var openWindows: [NSWindow] = []
    private let applyPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void
    private let isOnActiveSpace: @MainActor (NSWindow) -> Bool

    /// - Parameters:
    ///   - isOnActiveSpace: Whether a window is on the Space being shown — or,
    ///     minimised, would come back there (`NSWindow.isOnActiveSpace`). A
    ///     minimised Dashboard does not make the Dock icon go.
    ///   - workspaceNotifications: Where Space changes are posted; `nil` to
    ///     call `windowsMayBeOnActiveSpace()` by hand.
    ///   - appNotifications: Where windows becoming key are posted; likewise.
    init(applyPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { NSApp.setActivationPolicy($0) },
         isOnActiveSpace: @escaping @MainActor (NSWindow) -> Bool = { $0.isOnActiveSpace },
         workspaceNotifications: NotificationCenter? = nil,
         appNotifications: NotificationCenter? = nil) {
        self.applyPolicy = applyPolicy
        self.isOnActiveSpace = isOnActiveSpace
        super.init()
        let selector = #selector(windowsMayBeOnActiveSpace)
        workspaceNotifications?.addObserver(self, selector: selector,
                                            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        appNotifications?.addObserver(self, selector: selector,
                                      name: NSWindow.didBecomeKeyNotification, object: nil)
    }

    /// Call when a normal window is shown. Opening the same window twice is
    /// fine. Returns whether this made AudioWhisper a regular app — which, on
    /// a full-screen Space, moves the user to a desktop shortly afterwards.
    @discardableResult
    func windowDidOpen(_ window: NSWindow) -> Bool {
        if !openWindows.contains(where: { $0 === window }) {
            openWindows.append(window)
        }
        guard policy == .accessory else { return false }
        apply(.regular)
        return true
    }

    /// Call when a normal window closes. Once the last one has, the Dock icon
    /// goes away again.
    func windowWillClose(_ window: NSWindow) {
        guard let index = openWindows.firstIndex(where: { $0 === window }) else { return }
        openWindows.remove(at: index)
        if openWindows.isEmpty, policy == .regular {
            apply(.accessory)
        }
    }

    /// Call before the status menu opens. Away from AudioWhisper's windows the
    /// user may be on a full-screen Space, where the menu could not open.
    func statusMenuWillOpen() {
        guard policy == .regular, !openWindows.contains(where: isOnActiveSpace) else { return }
        apply(.accessory)
    }

    /// Called when the Space being shown changes or a window becomes key: back
    /// with one of its windows, AudioWhisper is a regular app again. On a
    /// Space that already shows its window, that moves nothing.
    @objc func windowsMayBeOnActiveSpace() {
        guard policy == .accessory, openWindows.contains(where: isOnActiveSpace) else { return }
        apply(.regular)
    }

    private func apply(_ newPolicy: NSApplication.ActivationPolicy) {
        policy = newPolicy
        applyPolicy(newPolicy)
    }
}
