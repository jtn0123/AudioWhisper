import Foundation
import os.log

/// Turns errors from Python, MLX, Hugging Face and the file system into
/// sentences a user can act on. The original text is logged, so the cause
/// still reaches diagnostics when the message on screen is simplified.
enum RebuildErrorText {
    private static let logger = Logger(subsystem: "com.audiowhisper.app", category: "UserError")

    static func userMessage(for error: Error) -> String {
        let raw = error.localizedDescription
        guard let friendly = friendly(error), friendly != raw else { return raw }
        logger.error("Shown as \"\(friendly, privacy: .public)\": \(raw, privacy: .public)")
        return friendly
    }

    static func friendly(_ error: Error) -> String? {
        if error is CancellationError { return "Cancelled." }
        if let daemon = error as? MLDaemonError { return message(for: daemon) }
        if case SpeechToTextError.localTranscriptionFailed(let inner) = error { return friendly(inner) }
        let nsError = error as NSError
        if isDiskFull(nsError) { return "Your disk is full. Free up some space, then try again." }
        if isOffline(nsError) { return "You're offline. Connect to the internet to download models, then try again." }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error { return friendly(underlying) }
        return nil
    }

    static let engineHint = "Try again; if it keeps happening, choose Check installation in Setup."

    private static func message(for error: MLDaemonError) -> String {
        switch error {
        case .timeout:
            return "The local model took too long and was restarted. \(engineHint)"
        case .restartLimitReached:
            return "The local model engine keeps stopping. Choose Check installation in Setup, or restart AudioWhisper."
        case .scriptNotFound, .daemonUnavailable, .writeFailed, .invalidResponse:
            return "The local model engine isn't responding. \(engineHint)"
        case .remoteError(let message):
            return remoteMessage(message)
        }
    }

    private static func remoteMessage(_ message: String) -> String {
        let text = message.lowercased()
        if text.contains("insufficient memory") || text.contains("out of memory") || text.contains("memoryerror") {
            return "Your Mac ran out of memory running the model. Close other apps or choose a smaller model."
        }
        if text.contains("local cache") || text.contains("localentrynotfound") || text.contains("snapshot") {
            return "The model isn't fully downloaded. Install it again in Setup."
        }
        if text.contains("no space left") { return "Your disk is full. Free up some space, then try again." }
        return "The local model reported a problem. \(engineHint)"
    }

    private static func isDiskFull(_ error: NSError) -> Bool {
        (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError)
            || (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
    }

    private static func isOffline(_ error: NSError) -> Bool {
        guard error.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorDNSLookupFailed].contains(error.code)
    }
}
