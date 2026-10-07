import AppKit
import AVFoundation
import Observation

/// Refreshes device descriptions without requesting permission or replacing
/// a saved UID. Device objects stay inside the enumerator.
@MainActor
@Observable
final class RebuildMicrophoneInputs {
    struct Input: Identifiable, Equatable {
        let id: String
        let name: String
    }

    private(set) var devices: [Input] = []
    private let isAuthorized: () -> Bool
    private let enumerate: () -> [Input]
    private let center: NotificationCenter
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(
        center: NotificationCenter = .default,
        isAuthorized: @escaping () -> Bool = { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized },
        enumerate: @escaping () -> [Input] = {
            AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
                .devices.map { Input(id: $0.uniqueID, name: $0.localizedName) }
        }
    ) {
        self.center = center
        self.isAuthorized = isAuthorized
        self.enumerate = enumerate
    }

    deinit { observers.forEach { center.removeObserver($0) } }

    func startObserving() {
        if observers.isEmpty {
            for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification,
                         NSApplication.didBecomeActiveNotification] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                })
            }
        }
        refresh()
    }

    func refresh() { devices = isAuthorized() ? enumerate() : [] }
}
