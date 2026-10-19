import Foundation

enum MeetingAudioSource: String, Codable, CaseIterable, Sendable {
    case microphone, system
    var title: String { self == .microphone ? "Microphone" : "System audio" }
}

struct MeetingAudioChunk: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let source: MeetingAudioSource
    let filename: String
    let offset: TimeInterval
    let duration: TimeInterval
    var hasSignal: Bool?
}

struct MeetingSpeakerSpan {
    let start: Double
    let end: Double
    let label: String
}

struct MeetingListEntry: Identifiable, Sendable {
    let id: UUID
    let title: String
    let startedAt: Date
    let status: MeetingDocument.Status
    init(_ document: MeetingDocument) {
        id = document.id
        title = document.title
        startedAt = document.startedAt
        status = document.status
    }
}

struct MeetingInventory {
    let entries: [MeetingListEntry]
    let unreadableCount: Int
    let hasMore: Bool
}

struct MeetingSegment: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    let source: MeetingAudioSource
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    var speaker: String?
}

struct MeetingDocument: Codable, Identifiable, Sendable {
    enum Status: String, Codable, Sendable { case recording, captured, processing, complete, interrupted, failed }
    let schemaVersion: Int
    let id: UUID
    var title: String
    let startedAt: Date
    var status: Status
    var chunks: [MeetingAudioChunk]
    var segments: [MeetingSegment]
    var summary: String?
    var note: String?
    var audioRetained: Bool

    init(title: String) {
        schemaVersion = 1
        id = UUID()
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Meeting" : String(title.prefix(120))
        startedAt = Date()
        status = .recording
        chunks = []
        segments = []
        audioRetained = true
    }

    var transcript: String {
        segments.sorted { $0.start < $1.start }.map {
            "[\(Self.timestamp($0.start))] \($0.source.title)\($0.speaker.map { " · " + $0 } ?? ""): \($0.text)"
        }.joined(separator: "\n")
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", value / 3600, (value / 60) % 60, value % 60)
    }
}

enum MeetingError: String, LocalizedError {
    case busy = "Finish the current dictation or model operation first."
    case microphone = "Allow microphone access for microphone capture, then start again."
    case systemPermission = "Allow Screen & System Audio Recording in System Settings, then reopen AudioWhisper if requested."
    case noDisplay = "System audio capture needs an available display. Try microphone-only capture."
    case audio = "Audio capture failed. Closed chunks were kept for recovery."
    case bounds = "Meetings are limited to 30 minutes in this first version."
    case document = "This meeting is invalid or too large. Its source files have been kept."
    case model = "Install the selected Whisper model in Models & setup before processing this meeting."
    var errorDescription: String? { rawValue }
}
