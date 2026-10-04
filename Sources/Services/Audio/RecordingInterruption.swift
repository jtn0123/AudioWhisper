import Foundation

/// A recorder event belongs to the capture that produced it, even if delivery
/// is delayed until another session has started.
enum RecordingInterruption {
    case finished(sessionID: UUID, audio: URL?, duration: TimeInterval?)
    case failed(sessionID: UUID, message: String)

    var sessionID: UUID {
        switch self {
        case .finished(let id, _, _), .failed(let id, _): return id
        }
    }
}

extension Notification.Name {
    static let recordingInterrupted = Notification.Name("AudioWhisper.recordingInterrupted")
}
