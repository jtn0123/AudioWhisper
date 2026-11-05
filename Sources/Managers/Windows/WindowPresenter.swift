import AppKit

/// Brings AudioWhisper's normal windows on screen where a normal window
/// belongs: on a desktop, never on top of another app's full-screen window.
///
/// Normal windows have an explicit primary role. Activation is allowed to
/// settle before ordering them, but later Space changes never reparent them:
/// a Space notification cannot distinguish a desktop from another app's
/// full-screen Space. Only the recording HUD has overlay eligibility.
@MainActor
internal final class WindowPresenter {
    struct Environment {
        var isAppActive: @MainActor () -> Bool
        var activateApp: @MainActor () -> Void
        var requestAttention: @MainActor () -> Void
        var after: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
        var orderFront: @MainActor (NSWindow) -> Void
        var appNotifications: NotificationCenter
        var workspaceNotifications: NotificationCenter
    }

    static let shared = WindowPresenter(environment: .live, policy: .shared)

    /// Longest wait for the Space switch that follows becoming a regular app.
    /// Measured at 0.29 s; on a desktop no switch comes, so this is the delay.
    static let settleDelay: TimeInterval = 0.4
    /// How long to wait for activation before bouncing the Dock icon.
    static let activationTimeout: TimeInterval = 1.0
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

    init(environment: Environment, policy: ActivationPolicyController) {
        self.environment = environment
        self.policy = policy
    }

    /// Shows `window` — restoring it if minimised — once it can appear on a
    /// desktop. Asking again while it waits does not show it twice.
    func present(_ window: NSWindow) {
        DiagnosticController.shared.window(.requested, window)
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
            self?.pending.forEach { DiagnosticController.shared.window(.activated, $0) }
            self?.awaitSpaceSwitch()
        }
        pending.forEach { DiagnosticController.shared.window(.activationRequested, $0) }
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
            pending.forEach { DiagnosticController.shared.window(.spaceChanged, $0) }
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
        windows.forEach { DiagnosticController.shared.window(.orderedFront, $0) }
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
        activateApp: { if !WindowServer.isRunningUnderTests { NSApp.activate() } },
        requestAttention: {
            if !WindowServer.isRunningUnderTests { _ = NSApp.requestUserAttention(.informationalRequest) }
        },
        after: runOnMainQueue(after:_:),
        orderFront: { window in
            guard !WindowServer.isRunningUnderTests else { return }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        },
        appNotifications: .default,
        workspaceNotifications: NSWorkspace.shared.notificationCenter
    )

    @MainActor
    static func runOnMainQueue(after delay: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { body() }
        }
    }
}
