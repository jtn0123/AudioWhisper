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
    nonisolated private static func tap(into feed: AudioFeed) -> AVAudioNodeTapBlock {
        { buffer, _ in feed.receive(buffer) }
    }

    /// Releases the microphone before sleep and opens it again after wake,
    /// and follows changes of the system default input. Each registration is
    /// removed when the returned token is released.
    func watchSystem() -> [AnyObject] {
        let workspace = NSWorkspace.shared.notificationCenter
        let sleep = workspace.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.coolDown() }
        }
        let wake = workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
        return [
            Registration { workspace.removeObserver(sleep) },
            Registration { workspace.removeObserver(wake) },
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
    static func watchDefaultInput(_ changed: @escaping @MainActor () -> Void) -> Registration {
        var address = defaultInputAddress
        let listener: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { changed() } }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        return Registration {
            var address = defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
    }

    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}
