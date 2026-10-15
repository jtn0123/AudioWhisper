import os.log

/// Lowers other audio for the length of a recording and puts it back.
///
/// What was lowered is written to disk before the volume moves, keyed by
/// device UID, so a crash mid-recording is undone at the next launch and a
/// device that disappears meanwhile (AirPods disconnecting) is put back when
/// it is next seen. The volume is only put back while it still sits where it
/// was lowered to: if the user changed it during the recording, their choice
/// stands.
@MainActor
final class OutputDucker {
    struct Lowered: Codable, Equatable {
        let original: Float32
        let lowered: Float32
    }

    static let shared = OutputDucker()

    /// Other audio drops to this fraction of its volume.
    static let level: Float32 = 0.3
    /// Volumes this close count as the same setting. The volume keys move in
    /// steps of 1/16, so a single press is always seen as the user's choice.
    static let tolerance: Float32 = 0.02

    private let controller: AudioOutputVolumeControlling

    init(controller: AudioOutputVolumeControlling = CoreAudioOutputVolumeController()) {
        self.controller = controller
    }

    /// Lowers the default output device.
    func duck() {
        restore()
        guard let device = controller.defaultOutputDevice(),
              let uid = controller.uid(of: device),
              AppDefaults.loweredOutputVolumes[uid] == nil,
              let original = controller.volume(of: device),
              original > Self.tolerance else { return }
        let target = original * Self.level
        AppDefaults.loweredOutputVolumes[uid] = Lowered(original: original, lowered: target)
        guard controller.setVolume(target, of: device) else {
            AppDefaults.loweredOutputVolumes[uid] = nil
            return
        }
        // Devices round to their own steps; remember where it actually landed.
        let landed = controller.volume(of: device) ?? target
        AppDefaults.loweredOutputVolumes[uid] = Lowered(original: original, lowered: landed)
    }

    /// Puts back every lowered device that is present. Safe to call when
    /// nothing was lowered.
    func restore() {
        var pending = AppDefaults.loweredOutputVolumes
        guard !pending.isEmpty else { return }
        for (uid, entry) in pending {
            guard let device = controller.device(withUID: uid),
                  let current = controller.volume(of: device) else { continue }
            if abs(current - entry.lowered) <= Self.tolerance {
                if !controller.setVolume(entry.original, of: device) {
                    Logger.audioRecorder.warning("Could not put back the output volume of \(uid, privacy: .public)")
                }
            }
            pending[uid] = nil
        }
        AppDefaults.loweredOutputVolumes = pending
    }
}
