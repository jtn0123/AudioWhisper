import AppKit

/// Brings AudioWhisper's normal windows on screen where a normal window
/// belongs: on a desktop, never on top of another app's full-screen window.
///
/// The Dashboard kept opening over full-screen apps, and two timings caused
/// it, both measured:
///
/// * A window brought in while AudioWhisper is in the background lands on the
///   Space the user is looking at, full-screen or not.
/// * Clicking the menu bar icon makes AudioWhisper active *without* leaving a
///   full-screen Space — a menu bar app may be active there. Becoming a
///   regular app for the Dashboard (`ActivationPolicyController`) is what
///   makes macOS move to a desktop, about 0.3 s later. A window brought in
///   before that move is left behind on the full-screen Space.
///
/// So a window is shown only once AudioWhisper is active and, if the app has
/// just become regular, once the Space has switched — or `settleDelay` has
/// passed with no switch, because the user was on a desktop already. If a
/// switch still arrives after the window is up, the window follows it.
@MainActor
internal final class WindowPresenter {
    struct Environment {
        var isAppActive: @MainActor () -> Bool
        var activateApp: @MainActor () -> Void
        var requestAttention: @MainActor () -> Void
        var after: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
        var orderFront: @MainActor (NSWindow) -> Void
        /// Whether a window is on screen, but not on the Space being shown.
        var isStranded: @MainActor (NSWindow) -> Bool
        var moveToActiveSpace: @MainActor (NSWindow) -> Void
        var appNotifications: NotificationCenter
        var workspaceNotifications: NotificationCenter
    }

    static let shared = WindowPresenter(environment: .live, policy: .shared)

    /// Longest wait for the Space switch that follows becoming a regular app.
    /// Measured at 0.29 s; on a desktop no switch comes, so this is the delay.
    static let settleDelay: TimeInterval = 0.4
    /// How long to wait for activation before bouncing the Dock icon.
    static let activationTimeout: TimeInterval = 1.0
    /// How long after showing a window a Space switch is taken to be the one
    /// that left it behind, rather than the user changing Space.
    static let lateSwitchWindow: TimeInterval = 1.5

    private enum State: Equatable {
        case idle
        case awaitingActivation
        case settling(generation: Int)
    }

    private let environment: Environment
    private let policy: ActivationPolicyController
    private var state: State = .idle
    private var generation = 0
    private var pending: [NSWindow] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var lateSwitchObserver: NSObjectProtocol?

    init(environment: Environment, policy: ActivationPolicyController) {
        self.environment = environment
        self.policy = policy
    }

    /// Shows `window` — restoring it if minimised — once it can appear on a
    /// desktop. Asking again while it waits does not show it twice.
    func present(_ window: NSWindow) {
        let becameRegular = policy.windowDidOpen(window)
        if !pending.contains(where: { $0 === window }) {
            pending.append(window)
        }
        guard state == .idle else { return }

        if !environment.isAppActive() {
            awaitActivation()
        } else if becameRegular {
            awaitSpaceSwitch()
        } else {
            showPending()
        }
    }

    /// Activation is cooperative since macOS 14 and is refused while the user
    /// is typing in another app. The window then waits, the Dock icon bounces,
    /// and it appears when the user activates AudioWhisper.
    private func awaitActivation() {
        state = .awaitingActivation
        observe(NSApplication.didBecomeActiveNotification, on: environment.appNotifications) { [weak self] in
            // Activation can itself move to another Space.
            self?.awaitSpaceSwitch()
        }
        environment.activateApp()
        environment.after(Self.activationTimeout) { [weak self] in
            guard let self, state == .awaitingActivation else { return }
            environment.requestAttention()
        }
    }

    private func awaitSpaceSwitch() {
        removeObservers()
        generation += 1
        let current = State.settling(generation: generation)
        state = current
        observe(NSWorkspace.activeSpaceDidChangeNotification, on: environment.workspaceNotifications) { [weak self] in
            guard let self, state == current else { return }
            showPending()
        }
        environment.after(Self.settleDelay) { [weak self] in
            guard let self, state == current else { return }
            showPending()
        }
    }

    private func showPending() {
        removeObservers()
        state = .idle
        generation += 1
        let windows = pending
        pending = []
        windows.forEach(environment.orderFront)
        followLateSpaceSwitch(of: windows)
    }

    /// A switch slower than `settleDelay` would strand the windows just shown
    /// on the Space being left; this moves them after it.
    private func followLateSpaceSwitch(of windows: [NSWindow]) {
        stopFollowingLateSpaceSwitch()
        let center = environment.workspaceNotifications
        lateSwitchObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.moveStranded(windows) }
        }
        let watch = generation
        environment.after(Self.lateSwitchWindow) { [weak self] in
            guard let self, generation == watch else { return }
            stopFollowingLateSpaceSwitch()
        }
    }

    private func moveStranded(_ windows: [NSWindow]) {
        stopFollowingLateSpaceSwitch()
        windows.filter(environment.isStranded).forEach(environment.moveToActiveSpace)
    }

    private func stopFollowingLateSpaceSwitch() {
        if let lateSwitchObserver {
            environment.workspaceNotifications.removeObserver(lateSwitchObserver)
        }
        lateSwitchObserver = nil
    }

    private func observe(_ name: Notification.Name, on center: NotificationCenter,
                         _ body: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { body() }
        }
        observers.append((center, token))
    }

    private func removeObservers() {
        observers.forEach { center, token in center.removeObserver(token) }
        observers = []
    }
}

extension WindowPresenter.Environment {
    static let live = WindowPresenter.Environment(
        isAppActive: { NSApp.isActive },
        activateApp: { NSApp.activate() },
        requestAttention: { _ = NSApp.requestUserAttention(.informationalRequest) },
        after: { delay, body in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { body() }
            }
        },
        orderFront: { window in
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        },
        isStranded: { $0.isVisible && !$0.isOnActiveSpace },
        moveToActiveSpace: { window in
            // `.moveToActiveSpace` is the documented way to bring a window to
            // the Space being shown when it is ordered front. It is put back
            // afterwards, so the window then stays where the user leaves it.
            let behavior = window.collectionBehavior
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                window.collectionBehavior = behavior
            }
        },
        appNotifications: .default,
        workspaceNotifications: NSWorkspace.shared.notificationCenter
    )
}
