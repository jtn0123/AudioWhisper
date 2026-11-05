/// Delivery and clipboard restoration are separate facts. A successful paste
/// does not mean that the transcript is still on the clipboard.
enum RebuildDeliveryStatus: Equatable {
    case none, delivering, copied, pasted(clipboardRestored: Bool), unverified(clipboardRestored: Bool), manual

    var title: String {
        switch self {
        case .none, .delivering: return "Transcript ready"
        case .copied: return "Copied to your clipboard"
        case .pasted: return "Text pasted"
        case .unverified: return "Paste sent · confirmation unavailable"
        case .manual: return "Paste manually with Command V"
        }
    }

    var detail: String {
        switch self {
        case .none, .delivering: return "Delivering your transcript…"
        case .copied: return "Press Command V in the app where you want your text."
        case .pasted(true), .unverified(true):
            return "Your previous clipboard was restored. Use Copy text to copy this transcript again."
        case .pasted(false), .unverified(false): return "Use Copy text if you need this transcript again."
        case .manual: return "If needed, use Copy text below, then paste in your app."
        }
    }

    var announcement: String { title + ". " + detail }
}

enum RebuildLifecycleAnnouncement {
    static func message(phase: RebuildPhase, previous: RebuildPhase, notice: String?) -> String? {
        guard phase != previous else { return nil }
        switch phase {
        case .starting: return "Connecting microphone."
        case .recording: return "Recording started."
        case .transcribing: return "Recording stopped. Transcribing."
        case .failed: return notice ?? "Dictation failed. Try again."
        case .idle: return previous.isBusy ? "Dictation cancelled." : nil
        case .completed: return nil // Announce once delivery and restoration have finished.
        }
    }
}
