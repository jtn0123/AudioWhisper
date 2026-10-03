import AppKit
@testable import AudioWhisper

/// Stands in for `StandardWindow.presenter` while a test opens a real window
/// manager's window: it records the windows it would show and puts nothing on
/// screen. Activation is taken as done and timers fire at once, so a window
/// counts as shown as soon as it is presented.
@MainActor
final class PresenterSpy {
    private(set) var shown: [NSWindow] = []
    private var original: WindowPresenter?

    /// Makes `StandardWindow` present through this spy until `uninstall()`.
    func install() {
        original = StandardWindow.presenter
        let environment = WindowPresenter.Environment(
            isAppActive: { true },
            activateApp: {},
            requestAttention: {},
            after: { _, body in body() },
            orderFront: { [unowned self] in shown.append($0) },
            isStranded: { _ in false },
            moveToActiveSpace: { _ in },
            appNotifications: NotificationCenter(),
            workspaceNotifications: NotificationCenter()
        )
        StandardWindow.presenter = WindowPresenter(environment: environment,
                                                   policy: ActivationPolicyController { _ in })
    }

    func uninstall() {
        if let original {
            StandardWindow.presenter = original
        }
        original = nil
    }
}
