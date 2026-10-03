import Foundation
import AppKit

internal enum PressAndHoldMode: String, CaseIterable, Identifiable {
    case hold
    case toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hold:
            return "Press and Hold"
        case .toggle:
            return "Press to Toggle"
        }
    }
}

internal enum PressAndHoldKey: String, CaseIterable, Identifiable {
    case rightCommand
    case leftCommand
    case rightOption
    case leftOption
    case rightControl
    case leftControl
    case globe

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rightCommand:
            return "Right Command (⌘)"
        case .leftCommand:
            return "Left Command (⌘)"
        case .rightOption:
            return "Right Option (⌥)"
        case .leftOption:
            return "Left Option (⌥)"
        case .rightControl:
            return "Right Control (⌃)"
        case .leftControl:
            return "Left Control (⌃)"
        case .globe:
            return "Globe / Fn (🌐)"
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .rightCommand:
            return 54
        case .leftCommand:
            return 55
        case .rightOption:
            return 61
        case .leftOption:
            return 58
        case .rightControl:
            return 62
        case .leftControl:
            return 59
        case .globe:
            return 63
        }
    }

    /// Modifier flag that macOS sets when the key is active.
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightCommand, .leftCommand:
            return .command
        case .rightOption, .leftOption:
            return .option
        case .rightControl, .leftControl:
            return .control
        case .globe:
            return .function
        }
    }

    /// Device-dependent modifier mask bit that distinguishes the *specific* physical
    /// key (left vs. right). These are the `NX_DEVICE*KEYMASK` constants from
    /// `IOKit/hidsystem/IOLLEvent.h`, tested against `NSEvent.modifierFlags.rawValue`.
    ///
    /// The device-independent `modifierFlag` (`.command`, `.option`, ...) is identical
    /// for the left and right key of a pair, so it cannot tell them apart. Using the
    /// device-dependent bit ensures e.g. releasing Right-Command is not masked by a
    /// still-held Left-Command.
    ///
    /// `nil` for the Globe/Fn key, which has no left/right variant — callers fall back
    /// to the device-independent `.function` flag for it.
    var deviceDependentMask: UInt? {
        switch self {
        case .leftCommand:
            return 0x00000008  // NX_DEVICELCMDKEYMASK
        case .rightCommand:
            return 0x00000010  // NX_DEVICERCMDKEYMASK
        case .leftOption:
            return 0x00000020  // NX_DEVICELALTKEYMASK
        case .rightOption:
            return 0x00000040  // NX_DEVICERALTKEYMASK
        case .leftControl:
            return 0x00000001  // NX_DEVICELCTLKEYMASK
        case .rightControl:
            return 0x00002000  // NX_DEVICERCTLKEYMASK
        case .globe:
            return nil
        }
    }

    /// Returns whether this specific physical key is currently down, given a set of
    /// `NSEvent.ModifierFlags`. Uses the device-dependent mask to distinguish left vs.
    /// right; falls back to the device-independent flag for the Globe/Fn key.
    func isKeyDown(in flags: NSEvent.ModifierFlags) -> Bool {
        if let mask = deviceDependentMask {
            return (flags.rawValue & mask) == mask
        }
        return flags.contains(modifierFlag)
    }
}

internal struct PressAndHoldConfiguration: Equatable {
    var enabled: Bool
    var key: PressAndHoldKey
    var mode: PressAndHoldMode

    static let defaults = PressAndHoldConfiguration(
        enabled: true,
        key: .rightCommand,
        mode: .hold
    )
}

internal enum PressAndHoldSettings {
    private static let enabledKey = "pressAndHoldEnabled"
    private static let keyIdentifierKey = "pressAndHoldKeyIdentifier"
    private static let modeKey = "pressAndHoldMode"

    // D4: defaults to AppDefaults.defaults, not .standard, so this honours the
    // test-suite redirection. It read .standard while tests wrote the redirected
    // store, which made AppDelegateHotkeysTests fail under --parallel.
    static func configuration(using defaults: UserDefaults = AppDefaults.defaults) -> PressAndHoldConfiguration {
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? PressAndHoldConfiguration.defaults.enabled
        let keyIdentifier = defaults.string(forKey: keyIdentifierKey) ?? PressAndHoldConfiguration.defaults.key.rawValue
        let modeIdentifier = defaults.string(forKey: modeKey) ?? PressAndHoldConfiguration.defaults.mode.rawValue

        let key = PressAndHoldKey(rawValue: keyIdentifier)
            ?? legacyKey(from: keyIdentifier)
            ?? PressAndHoldConfiguration.defaults.key
        let mode = PressAndHoldMode(rawValue: modeIdentifier) ?? PressAndHoldConfiguration.defaults.mode

        return PressAndHoldConfiguration(enabled: enabled, key: key, mode: mode)
    }

    static func update(_ configuration: PressAndHoldConfiguration, using defaults: UserDefaults = AppDefaults.defaults) {
        defaults.set(configuration.enabled, forKey: enabledKey)
        defaults.set(configuration.key.rawValue, forKey: keyIdentifierKey)
        defaults.set(configuration.mode.rawValue, forKey: modeKey)

        NotificationCenter.default.post(name: .pressAndHoldSettingsChanged, object: configuration)
    }

    private static func legacyKey(from rawValue: String) -> PressAndHoldKey? {
        switch rawValue {
        case "option":
            return .leftOption
        case "control":
            return .leftControl
        case "fn", "globe":
            return .globe
        default:
            return nil
        }
    }
}

/// Observes keyboard events so that modifier-only keys (e.g. right command)
/// can trigger recording, whichever app is focused.
///
/// That takes two monitors per event type. A global monitor sees only events
/// sent to *other* apps, and a local monitor only those sent to this one. This
/// used to install the global ones alone, so the key did nothing while one of
/// AudioWhisper's own windows — the Dashboard — had focus, and a key released
/// while the Dashboard was focused never ended a hold-to-record.
///
/// A5: `@unchecked Sendable` rather than `@MainActor`. This type is genuinely
/// multi-threaded *by design*, and marking it `@MainActor` would contradict that:
///
///   * `isPressed` is guarded by `os_unfair_lock` because it sits in the keyboard
///     hot path, where an actor hop would be too expensive.
///   * State transitions are deliberately serialised onto `monitorQueue`, a
///     private serial queue, so events are ordered independently of which thread
///     NSEvent delivers them on.
///   * The watchdog `Timer` is installed on the main run loop, but a release
///     clears it from `monitorQueue`, so the reference itself is lock-guarded too.
///
/// Without this, capturing `self` in the watchdog's `@Sendable` timer block warns.
/// The annotation asserts what the locking above already provides. (I tried
/// `@MainActor` first; it forces `processTransition` off `monitorQueue` and
/// produced five new warnings instead of removing one — the wrong fix.)
internal final class PressAndHoldKeyMonitor: @unchecked Sendable {
    typealias EventMonitorFactory = (NSEvent.EventTypeMask, @escaping (NSEvent) -> Void) -> Any?
    typealias LocalEventMonitorFactory = (NSEvent.EventTypeMask, @escaping (NSEvent) -> NSEvent?) -> Any?
    typealias EventMonitorRemoval = (Any) -> Void

    private let configuration: PressAndHoldConfiguration
    private let keyDownHandler: () -> Void
    private let keyUpHandler: (() -> Void)?
    private let addGlobalMonitor: EventMonitorFactory
    private let addLocalMonitor: LocalEventMonitorFactory
    private let removeMonitor: EventMonitorRemoval

    /// Every installed monitor, global and local, for `stop()` to remove.
    private var monitors: [Any] = []
    private let monitorQueue = DispatchQueue(label: "com.audiowhisper.pressAndHoldMonitor")

    /// Watchdog that reconciles `isPressed` against the real physical modifier state.
    /// Global flagsChanged events can be missed (sleep, monitor restart, event consumed
    /// elsewhere); without this, a missed key-up would leave `isPressed` stuck true and
    /// the next press ignored. Runs only while pressed and is cheap.
    ///
    /// Guarded by `watchdogLock`, and only touched through `swapWatchdogTimer`:
    /// it is installed on the main thread but cleared on `monitorQueue` when a
    /// release arrives. It used to be a plain property read and written from
    /// both, a data race on a class reference (and so on its retain count).
    private var _watchdogTimer: Timer?
    private var watchdogLock = os_unfair_lock()
    private static let watchdogInterval: TimeInterval = 0.25

    /// Reads the current physical modifier state. Injectable for tests.
    private let currentModifierFlags: () -> NSEvent.ModifierFlags

    // Thread-safe isPressed state using os_unfair_lock for minimal overhead in keyboard hot path
    private var isPressedLock = os_unfair_lock()
    private var _isPressed = false
    private var isPressed: Bool {
        get {
            os_unfair_lock_lock(&isPressedLock)
            defer { os_unfair_lock_unlock(&isPressedLock) }
            return _isPressed
        }
        set {
            os_unfair_lock_lock(&isPressedLock)
            defer { os_unfair_lock_unlock(&isPressedLock) }
            _isPressed = newValue
        }
    }

    /// Sets `isPressed` to `pressed` and reports whether that changed it, as one
    /// atomic step. Reading and then writing through the property takes the lock
    /// twice, so two concurrent key-downs could both read `false` and both fire
    /// the handler — the `downCount` 2 that the concurrency test caught.
    private func transitionPressed(to pressed: Bool) -> Bool {
        os_unfair_lock_lock(&isPressedLock)
        defer { os_unfair_lock_unlock(&isPressedLock) }
        guard _isPressed != pressed else { return false }
        _isPressed = pressed
        return true
    }

    /// Installs `timer` as the watchdog and returns the one it displaced, as one
    /// atomic step. The caller invalidates the returned timer.
    private func swapWatchdogTimer(_ timer: Timer?) -> Timer? {
        os_unfair_lock_lock(&watchdogLock)
        defer { os_unfair_lock_unlock(&watchdogLock) }
        let previous = _watchdogTimer
        _watchdogTimer = timer
        return previous
    }

    init(
        configuration: PressAndHoldConfiguration,
        keyDownHandler: @escaping () -> Void,
        keyUpHandler: (() -> Void)? = nil,
        addGlobalMonitor: @escaping EventMonitorFactory = NSEvent.addGlobalMonitorForEvents(matching:handler:),
        addLocalMonitor: @escaping LocalEventMonitorFactory = NSEvent.addLocalMonitorForEvents(matching:handler:),
        removeMonitor: @escaping EventMonitorRemoval = NSEvent.removeMonitor(_:),
        currentModifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    ) {
        self.configuration = configuration
        self.keyDownHandler = keyDownHandler
        self.keyUpHandler = keyUpHandler
        self.addGlobalMonitor = addGlobalMonitor
        self.addLocalMonitor = addLocalMonitor
        self.removeMonitor = removeMonitor
        self.currentModifierFlags = currentModifierFlags
    }

    func start() {
        stop()

        // Every `PressAndHoldKey` is a modifier, and a modifier key reports
        // only as `flagsChanged` — never as keyDown or keyUp.
        monitor(.flagsChanged) { [weak self] event in
            self?.handleModifierEvent(event)
        }
    }

    /// Sends `mask` events to `handler` whichever app they are for: a global
    /// monitor for other apps' events, a local one for this app's. The local
    /// one passes the event on — the key still does whatever it does in the
    /// focused window.
    private func monitor(_ mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) {
        if let global = addGlobalMonitor(mask, handler) {
            monitors.append(global)
        }
        let local = addLocalMonitor(mask) { event in
            handler(event)
            return event
        }
        if let local {
            monitors.append(local)
        }
    }

    func stop() {
        for monitor in monitors {
            removeMonitor(monitor)
        }
        monitors.removeAll()
        stopWatchdog()
        isPressed = false
    }

    deinit {
        stop()
    }

    private func handleModifierEvent(_ event: NSEvent) {
        guard event.type == .flagsChanged, event.keyCode == configuration.key.keyCode else { return }

        // Determine key state from the event's modifier flags, not by toggling.
        // This makes transitions idempotent - multiple events for the same state
        // are handled correctly by the guard in processTransition.
        //
        // Use the device-DEPENDENT mask so left vs. right modifier keys are
        // distinguished. The device-independent flag (.command/.option/...) is
        // identical for both keys of a pair, so holding the *other* side would
        // keep it set and a real release would never register.
        let keyIsCurrentlyDown = configuration.key.isKeyDown(in: event.modifierFlags)

        monitorQueue.async { [weak self] in
            self?.processTransition(isKeyDownEvent: keyIsCurrentlyDown)
        }
    }

    func processTransition(isKeyDownEvent: Bool) {
        guard transitionPressed(to: isKeyDownEvent) else { return }
        if isKeyDownEvent {
            startWatchdog()
            Task { @MainActor [keyDownHandler] in
                keyDownHandler()
            }
        } else {
            stopWatchdog()
            guard let keyUpHandler else { return }
            Task { @MainActor in
                keyUpHandler()
            }
        }
    }

    // MARK: - Watchdog

    /// Starts a periodic reconciliation timer while the key is held. If a key-up
    /// `flagsChanged` event is missed (sleep, monitor restart, event consumed
    /// elsewhere), `isPressed` would otherwise stay stuck `true` and block all
    /// future presses. The timer compares the real physical modifier state against
    /// `isPressed` and synthesizes a release if the key is no longer down.
    private func startWatchdog() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Re-check: a release may have already arrived before this main-actor hop.
            // One that lands between this check and the swap below leaves a timer
            // running while released; its first tick sees `isPressed` false and
            // stops it (`checkPhysicalKeyState`).
            guard self.isPressed else { return }
            let timer = Timer(
                timeInterval: Self.watchdogInterval,
                repeats: true
            ) { [weak self] _ in
                self?.checkPhysicalKeyState()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.swapWatchdogTimer(timer)?.invalidate()
        }
    }

    private func stopWatchdog() {
        // Invalidate synchronously. The previous implementation scheduled an
        // async Task — when called from `deinit`, `[weak self]` is already
        // nil by the time the Task runs, so the timer never gets invalidated
        // and the run-loop retained it for the next ~watchdogInterval seconds.
        // Capture the timer locally so we don't need to retain `self`, and
        // marshal to the main RunLoop (where the timer was scheduled) if
        // necessary. `invalidate()` must be called from the scheduling thread.
        guard let timer = swapWatchdogTimer(nil) else { return }
        if Thread.isMainThread {
            timer.invalidate()
        } else {
            RunLoop.main.perform { timer.invalidate() }
        }
    }

    /// Reconciles `isPressed` against the real modifier state. Runs on the main
    /// run loop via the watchdog timer.
    private func checkPhysicalKeyState() {
        guard isPressed else {
            stopWatchdog()
            return
        }
        let flags = currentModifierFlags()
        guard !configuration.key.isKeyDown(in: flags) else { return }

        // The configured key is no longer physically down but we still think it is —
        // a release event was missed. Treat it as a release.
        monitorQueue.async { [weak self] in
            self?.processTransition(isKeyDownEvent: false)
        }
    }
}
