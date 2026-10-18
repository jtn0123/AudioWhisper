import AppKit
import AVFAudio
import CoreAudio

extension WarmMicrophone where Input == PreparedAudioEngine {
    /// The real binding: prepares engines on its own worker, so warming up
    /// never makes a recording wait behind it.
    static func live(routing: AudioInputRouting) -> WarmMicrophone {
        let preparation = AudioHardwarePreparation<PreparedAudioEngine>()
        let microphone = WarmMicrophone(hardware: Hardware(
            open: { uid in
                try await preparation.run { try PreparedAudioEngine.make(routing: routing, selectedUID: uid) }
            },
            start: { prepared, feed in
                prepared.inputNode.installTap(
                    onBus: 0, bufferSize: 1024, format: prepared.format, block: Self.tap(into: feed))
                do { try prepared.engine.start() } catch {
                    prepared.inputNode.removeTap(onBus: 0)
                    throw error
                }
            },
            stop: { prepared in
                prepared.inputNode.removeTap(onBus: 0)
                prepared.engine.stop()
            },
            isCurrent: { prepared, uid in
                // A system-default input must still be the default.
                prepared.engine.isRunning && (!uid.isEmpty || (try? routing.resolveDevice("")) == prepared.device)
            },
            isBluetooth: { uid in
                guard let device = try? routing.resolveDevice(uid) else { return false }
                return AudioDeviceTransport.isBluetooth(device)
            }))
        microphone.isAllowed = {
            !AppEnvironment.isRunningTests && PermissionManager.shared.microphonePermissionState == .granted
        }
        return microphone
    }

    /// Built outside the main actor: the engine calls it on its audio thread.
    nonisolated static func tap(into feed: AudioFeed) -> AVAudioNodeTapBlock {
        { buffer, _ in feed.receive(buffer) }
    }
}

extension WarmMicrophone {
    /// Releases the microphone before sleep and opens it again after wake,
    /// and follows changes of the system default input. Each registration is
    /// removed when the returned token is released.
    func watchSystem(
        on workspace: NotificationCenter = NSWorkspace.shared.notificationCenter,
        wakeDelay: Duration = .seconds(2)
    ) -> [AnyObject] {
        let sleep = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.suspend() }
        }
        let wake = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleWake(after: wakeDelay) }
        }
        return [
            Registration { workspace.removeObserver(sleep) },
            Registration { [weak self] in
                workspace.removeObserver(wake)
                Task { @MainActor in self?.cancelScheduledWake() }
            },
            AudioDeviceTransport.watchDefaultInput { [weak self] in self?.invalidate() }
        ]
    }
}

/// Runs `cancel` when released.
final class Registration {
    private let cancel: () -> Void
    init(_ cancel: @escaping () -> Void) { self.cancel = cancel }
    deinit { cancel() }
}

/// The handlers behind `AudioDeviceTransport.watchDefaultInput`, keyed by the
/// token Core Audio passes back to the listener.
final class DefaultInputWatchers: @unchecked Sendable {
    static let shared = DefaultInputWatchers()
    private let lock = NSLock()
    private var handlers: [Int: @MainActor () -> Void] = [:]
    private var lastID = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return handlers.count
    }

    func add(_ handler: @escaping @MainActor () -> Void) -> Int {
        lock.lock()
        defer { lock.unlock() }
        lastID += 1
        handlers[lastID] = handler
        return lastID
    }

    func remove(_ id: Int) {
        lock.lock()
        defer { lock.unlock() }
        handlers[id] = nil
    }

    func handler(for id: Int) -> (@MainActor () -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[id]
    }
}

enum AudioDeviceTransport {
    static func isBluetooth(_ device: AudioDeviceID) -> Bool {
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return isBluetooth(transport: transport)
    }

    static func isBluetooth(transport: UInt32) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// Calls `changed` on the main actor whenever the system default input changes.
    ///
    /// This is the function-pointer listener, not the block one: Swift wraps a
    /// closure in a new block on every call into Core Audio, so
    /// `AudioObjectRemovePropertyListenerBlock` never matches the block that was
    /// added and the listener outlives its registration. Removal by proc and
    /// token is exact.
    static func watchDefaultInput(_ changed: @escaping @MainActor () -> Void) -> Registration {
        let token = UnsafeMutableRawPointer(bitPattern: DefaultInputWatchers.shared.add(changed))
        var address = defaultInputAddress
        AudioObjectAddPropertyListener(AudioObjectID(kAudioObjectSystemObject), &address, defaultInputChanged, token)
        return Registration {
            var address = defaultInputAddress
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject), &address, defaultInputChanged, token)
            DefaultInputWatchers.shared.remove(Int(bitPattern: token))
        }
    }

    /// Core Audio calls this on its own thread. The handler is looked up once on
    /// the main actor, so one removed in the meantime is not called.
    static let defaultInputChanged: AudioObjectPropertyListenerProc = { _, _, _, token in
        let id = Int(bitPattern: token)
        Task { @MainActor in DefaultInputWatchers.shared.handler(for: id)?() }
        return noErr
    }

    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}
