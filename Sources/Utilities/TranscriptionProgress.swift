import Foundation

/// Progress follows the task that produced it, including delayed provider callbacks.
enum TranscriptionProgress {
    @TaskLocal static var sessionID: UUID?
    @TaskLocal static var pipelineConfig: TranscriptionPipelineConfig?

    static func post(_ message: String, sessionID: UUID?) {
        NotificationCenter.default.post(
            name: .transcriptionProgress,
            object: message,
            userInfo: sessionID.map { ["sessionID": $0] }
        )
    }
}
