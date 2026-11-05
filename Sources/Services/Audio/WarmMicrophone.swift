import Foundation

/// Keeps the microphone running between recordings, when the user asks, so
/// the next recording starts at once with the moment before the shortcut
/// already captured.
///
/// A held input is lent to a recording only if it is still the microphone the
/// recording would choose and audio is still arriving; anything else falls
/// back to the ordinary cold start. Bluetooth inputs are never held: keeping
/// one open drops the headset to call quality for everything it plays.
///
/// Generic over the input so the decisions are tested without hardware; the
/// app uses `PreparedAudioEngine` (see `WarmMicrophone+Live.swift`).
@MainActor
final class WarmMicrophone<Input> {
    struct Hardware {
        /// Prepares an input for `uid` (empty means the system default).
        var open: @MainActor (_ uid: String) async throws -> Input
        /// Starts it, sending every buffer to the feed.
        var start: (Input, AudioFeed) throws -> Void
        var stop: (Input) -> Void
        /// Still running, and still the device `uid` names.
        var isCurrent: (Input, _ uid: String) -> Bool
        var isBluetooth: (_ uid: String) -> Bool
    }

    struct Held {
        let input: Input
        let uid: String
        let feed: AudioFeed
    }

    enum State {
        case cold
        case opening(UUID)
        case warm(Held)
        case lent(Held)
    }

    /// A held input with no audio for this long is treated as dead.
    static var flowWindow: TimeInterval { 0.5 }

    private(set) var state: State = .cold
    private var suspended = false
    private var wakeTask: Task<Void, Never>?
    private let hardware: Hardware
    private let makeFeed: () -> AudioFeed
    var isEnabled: () -> Bool = { AppDefaults.keepMicrophoneReady }
    var isAllowed: () -> Bool = { false }
    var chosenUID: () -> String = { "" }
    var recordingActive: () -> Bool = { false }

    init(hardware: Hardware, makeFeed: @escaping () -> AudioFeed = { AudioFeed() }) {
        self.hardware = hardware
        self.makeFeed = makeFeed
    }

    var isWarm: Bool {
        if case .warm = state { return true }
        return false
    }

    /// Opens the microphone if it should be ready and is not; releases it if
    /// the user turned the setting off. Safe to call at any time.
    @discardableResult
    func refresh() -> Task<Void, Never>? {
        guard isEnabled(), isAllowed(), !suspended else {
            coolDown()
            return nil
        }
        guard case .cold = state, !recordingActive() else { return nil }
        let uid = chosenUID()
        guard !hardware.isBluetooth(uid) else { return nil }
        let token = UUID()
        state = .opening(token)
        return Task { await self.open(uid, token: token) }
    }

    private func open(_ uid: String, token: UUID) async {
        let input: Input
        do { input = try await hardware.open(uid) } catch {
            if case .opening(token) = state { state = .cold }
            return
        }
        // A recording that started meanwhile, or a cool-down, wins. The input
        // never started, but stop it anyway: every opened input is either held
        // or stopped, never left for deallocation to release.
        guard case .opening(token) = state, isEnabled(), isAllowed(), !suspended, !recordingActive() else {
            hardware.stop(input)
            if case .opening(token) = state { state = .cold }
            return
        }
        let feed = makeFeed()
        do {
            try hardware.start(input, feed)
            state = .warm(Held(input: input, uid: uid, feed: feed))
        } catch {
            hardware.stop(input)
            state = .cold
        }
    }

    /// The held input, if it is the one a recording from `uid` needs. Any
    /// other held input is released so it does not compete with the cold start.
    func lend(for uid: String) -> Held? {
        guard isEnabled(), isAllowed(), !suspended else {
            coolDown()
            return nil
        }
        guard case .warm(let held) = state else {
            if case .opening = state { state = .cold }
            return nil
        }
        guard held.uid == uid, hardware.isCurrent(held.input, held.uid),
              held.feed.isFlowing(within: Self.flowWindow) else {
            coolDown()
            return nil
        }
        state = .lent(held)
        return held
    }

    /// Takes the input back after the recording, keeping it running if it is
    /// still wanted and healthy.
    func reclaim(_ held: Held) {
        held.feed.detach()
        guard case .lent(let lent) = state, lent.feed === held.feed else {
            hardware.stop(held.input)
            return
        }
        guard isEnabled(), isAllowed(), !suspended, hardware.isCurrent(held.input, held.uid) else {
            hardware.stop(held.input)
            state = .cold
            refresh()
            return
        }
        state = .warm(held)
    }

    /// Releases a held input. One lent to a recording stays with it.
    func coolDown() {
        switch state {
        case .warm(let held):
            held.feed.detach()
            hardware.stop(held.input)
            state = .cold
        case .opening:
            state = .cold
        case .cold, .lent:
            break
        }
    }

    /// A recording may return its borrowed input after the sleep notification.
    /// Keep the suspension until wake so reclaim and settings changes cannot reopen it.
    func suspend() {
        cancelScheduledWake()
        suspended = true
        coolDown()
    }

    func scheduleWake(after delay: Duration) {
        cancelScheduledWake()
        wakeTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.suspended = false
            self.refresh()
        }
    }

    func cancelScheduledWake() {
        wakeTask?.cancel()
        wakeTask = nil
    }

    /// The device under a held input changed: open it again.
    func invalidate() {
        coolDown()
        refresh()
    }
}
