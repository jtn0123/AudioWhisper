import AVFoundation
import CoreAudio
import IOKit

/// A microphone the user ranked. The name is kept so the list can still say
/// which device it is while it is unplugged.
struct PreferredMicrophone: Codable, Equatable, Identifiable {
    let uid: String
    let name: String
    var id: String { uid }
}

extension Array where Element == PreferredMicrophone {
    /// Appends `microphone` unless it is already ranked.
    mutating func rank(_ microphone: PreferredMicrophone) {
        guard !contains(where: { $0.uid == microphone.uid }) else { return }
        append(microphone)
    }

    /// Swaps the microphone with its neighbour `offset` places away; nothing
    /// moves past either end.
    mutating func move(_ uid: String, by offset: Int) {
        guard let from = firstIndex(where: { $0.uid == uid }), indices.contains(from + offset) else { return }
        swapAt(from, from + offset)
    }
}

/// Decides which input a recording uses.
///
/// The first connected microphone in the user's ranking wins; with none
/// connected, the system default. A MacBook's built-in microphone is cut off
/// in hardware while the lid is closed and records only silence, so then it
/// is passed over for any other real input, ranked or not. With nothing else
/// connected it is still used, and the silence warning says what happened.
///
/// Live closures touch only AVFoundation device discovery and the IOKit
/// registry, both safe off the main thread, so a chooser may cross to the
/// preparation worker. Injected closures follow the same contract.
struct MicrophoneChooser: @unchecked Sendable {
    struct Input: Equatable {
        enum Kind: Equatable {
            case builtIn, external, virtual

            init(transport: UInt32) {
                switch transport {
                case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
                case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                     kAudioDeviceTransportTypeAutoAggregate: self = .virtual
                default: self = .external
                }
            }
        }

        let uid: String
        let kind: Kind
    }

    var connected: () -> [Input]
    var defaultUID: () -> String?
    var lidClosed: () -> Bool

    /// The UID to record from; empty means the system default.
    func choose(ranking: [PreferredMicrophone]) -> String {
        let inputs = connected()
        let lidClosed = lidClosed()
        let usable = inputs.filter { !(lidClosed && $0.kind == .builtIn) }
        if let ranked = ranking.first(where: { entry in usable.contains { $0.uid == entry.uid } }) {
            return ranked.uid
        }
        let systemDefault = defaultUID()
        guard lidClosed, inputs.first(where: { $0.uid == systemDefault })?.kind == .builtIn else { return "" }
        return usable.first { $0.kind == .external }?.uid ?? ""
    }

    static let live = Self(
        connected: {
            AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified)
                .devices.map { Input(uid: $0.uniqueID, kind: .init(transport: UInt32(bitPattern: $0.transportType))) }
        },
        defaultUID: { AVCaptureDevice.default(for: .audio)?.uniqueID },
        lidClosed: Clamshell.isClosed)
}

/// The lid of a MacBook.
enum Clamshell {
    /// Always false on a Mac without a lid.
    static func isClosed() -> Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }
        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return isClosed(state?.takeRetainedValue())
    }

    static func isClosed(_ state: CFTypeRef?) -> Bool {
        (state as? Bool) ?? false
    }
}
