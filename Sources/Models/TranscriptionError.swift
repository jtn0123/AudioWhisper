import Foundation
import AVFoundation

/// Represents different types of transcription errors with associated UI properties
internal enum TranscriptionError {
    case missingAPIKey(provider: String)
    case invalidAPIKey(provider: String)
    case microphonePermissionDenied
    case microphonePermissionRestricted
    case microphoneUnavailable
    case networkConnectionError
    case networkTimeout
    case transcriptionFailed(reason: String)
    case audioProcessingError
    case modelNotFound(model: String)
    case insufficientStorage
    case pythonConfigurationError
    case generalError(message: String)
    
    /// M13: Determines the error type from an `Error` object, preferring
    /// structural NSError `domain`/`code` matching over English substring
    /// matching. On localized macOS systems, AVFoundation / CoreFoundation /
    /// URLError descriptions are translated, so the legacy string-based
    /// `from(errorMessage:)` matcher silently loses recovery affordances.
    ///
    /// Currently covers the common cases we actually emit: URL/network,
    /// AVFoundation, Cocoa file/permission. Additional domains worth folding in
    /// as they turn up in crash logs include NSOSStatusErrorDomain (audio HAL),
    /// NSPOSIXErrorDomain (low-level FS), CFNetworkErrors numeric codes, and
    /// WhisperKitError / parakeet subprocess wrappers.
    static func from(error: Error) -> TranscriptionError {
        if let structural = fromStructured(error: error) {
            return structural
        }
        // English substring fallback for errors whose description carries the signal.
        return from(errorMessage: error.localizedDescription)
    }

    /// Structural domain/code matcher. Returns `nil` if the error does not map
    /// to a known structural case and the caller should fall back to substring
    /// matching.
    private static func fromStructured(error: Error) -> TranscriptionError? {
        // URLError covers most of what we care about for network failures and
        // does not depend on localized strings.
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .networkTimeout
            case .notConnectedToInternet, .networkConnectionLost,
                 .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost,
                 .secureConnectionFailed:
                return .networkConnectionError
            case .userAuthenticationRequired:
                return .invalidAPIKey(provider: "API")
            default:
                return .networkConnectionError
            }
        }

        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            if nsError.code == NSURLErrorTimedOut { return .networkTimeout }
            return .networkConnectionError

        case AVFoundationErrorDomain:
            // AVAuthorizationStatus / capture session errors. Map the common
            // permission-denied codes; otherwise treat as a microphone /
            // audio-processing failure rather than a generic message.
            let permissionDeniedCodes: Set<Int> = [
                AVError.applicationIsNotAuthorizedToUseDevice.rawValue,
                AVError.deviceNotConnected.rawValue
            ]
            if permissionDeniedCodes.contains(nsError.code) {
                return nsError.code == AVError.deviceNotConnected.rawValue
                    ? .microphoneUnavailable
                    : .microphonePermissionDenied
            }
            return .audioProcessingError

        case NSCocoaErrorDomain:
            // File-not-found-style errors → modelNotFound is too specific, so
            // we map disk-space to insufficientStorage and otherwise return nil
            // (let the substring matcher take a crack at it).
            if nsError.code == NSFileWriteOutOfSpaceError {
                return .insufficientStorage
            }
            return nil

        default:
            return nil
        }
    }

    /// Determines the error type from an error message
    static func from(errorMessage: String) -> TranscriptionError {
        let lowercased = errorMessage.lowercased()

        if let apiKey = apiKeyError(from: errorMessage, lowercased: lowercased) { return apiKey }
        if let mic = microphoneError(lowercased: lowercased) { return mic }
        if let net = networkError(lowercased: lowercased) { return net }

        if lowercased.contains("model")
            && (lowercased.contains("not found") || lowercased.contains("missing")) {
            return .modelNotFound(model: extractModel(from: errorMessage))
        }

        if lowercased.contains("storage")
            || lowercased.contains("disk space")
            || lowercased.contains("insufficient") {
            return .insufficientStorage
        }

        if let pyConfig = pythonConfigurationError(lowercased: lowercased) { return pyConfig }

        if lowercased.contains("audio")
            && (lowercased.contains("process") || lowercased.contains("convert")) {
            return .audioProcessingError
        }

        if lowercased.contains("transcription")
            || lowercased.contains("whisper")
            || lowercased.contains("gemini") {
            return .transcriptionFailed(reason: errorMessage)
        }

        return .generalError(message: errorMessage)
    }

    private static func apiKeyError(from message: String, lowercased: String) -> TranscriptionError? {
        let hasKeyToken = lowercased.contains("api key")
            || lowercased.contains("api_key")
            || lowercased.contains("apikey")
        guard hasKeyToken else { return nil }
        if lowercased.contains("missing") || lowercased.contains("not set") || lowercased.contains("required") {
            return .missingAPIKey(provider: extractProvider(from: message))
        }
        if lowercased.contains("invalid") || lowercased.contains("unauthorized") || lowercased.contains("401") {
            return .invalidAPIKey(provider: extractProvider(from: message))
        }
        return nil
    }

    private static func microphoneError(lowercased: String) -> TranscriptionError? {
        let hasMicToken = lowercased.contains("microphone")
            || lowercased.contains("audio input")
            || lowercased.contains("recording")
        guard hasMicToken else { return nil }
        if lowercased.contains("permission") || lowercased.contains("access") {
            if lowercased.contains("denied") { return .microphonePermissionDenied }
            if lowercased.contains("restricted") { return .microphonePermissionRestricted }
        }
        if lowercased.contains("unavailable") || lowercased.contains("not available") {
            return .microphoneUnavailable
        }
        return nil
    }

    private static func networkError(lowercased: String) -> TranscriptionError? {
        let hasNetToken = lowercased.contains("network")
            || lowercased.contains("connection")
            || lowercased.contains("internet")
        guard hasNetToken else { return nil }
        return lowercased.contains("timeout") ? .networkTimeout : .networkConnectionError
    }

    /// M12: only route to `pythonConfigurationError` when the message also signals
    /// a configuration problem. The previous broad check intercepted plain
    /// transcription failures (e.g. "Parakeet transcription failed: empty audio")
    /// before they could fall through to the whisper/audio branches.
    private static func pythonConfigurationError(lowercased: String) -> TranscriptionError? {
        let hasPyToken = lowercased.contains("python") || lowercased.contains("parakeet")
        guard hasPyToken else { return nil }
        let signals = ["not found", "not installed", "missing", "configure", "install"]
        guard signals.contains(where: { lowercased.contains($0) }) else { return nil }
        return .pythonConfigurationError
    }
    
    /// The primary button title for this error type
    var primaryButtonTitle: String {
        switch self {
        case .missingAPIKey, .invalidAPIKey:
            return "Open Settings"
        case .microphonePermissionDenied, .microphonePermissionRestricted:
            return "Open System Settings"
        case .microphoneUnavailable, .networkConnectionError, .networkTimeout,
             .audioProcessingError, .transcriptionFailed, .generalError:
            return "OK"
        case .modelNotFound:
            return "Download Model"
        case .insufficientStorage:
            return "Manage Storage"
        case .pythonConfigurationError:
            return "Configure Python"
        }
    }
    
    /// The secondary button title (if applicable)
    var secondaryButtonTitle: String? {
        switch self {
        case .missingAPIKey, .invalidAPIKey, .microphonePermissionDenied,
             .microphonePermissionRestricted, .modelNotFound, .pythonConfigurationError:
            return "Cancel"
        default:
            return nil
        }
    }
    
    /// Whether this error should show a settings button
    var shouldShowSettingsButton: Bool {
        switch self {
        case .missingAPIKey, .invalidAPIKey, .modelNotFound, .pythonConfigurationError:
            return true
        default:
            return false
        }
    }
    
    /// Whether this error should show system settings button
    var shouldShowSystemSettingsButton: Bool {
        switch self {
        case .microphonePermissionDenied, .microphonePermissionRestricted:
            return true
        default:
            return false
        }
    }
    
    /// A user-friendly error message
    var userMessage: String {
        switch self {
        case .missingAPIKey(let provider):
            return "\(provider) API key is required. Please add your API key in Settings."
        case .invalidAPIKey(let provider):
            return "Invalid \(provider) API key. Please check your API key in Settings."
        case .microphonePermissionDenied:
            return "Microphone access was denied. Please grant permission in System Settings > Privacy & Security > Microphone."
        case .microphonePermissionRestricted:
            return "Microphone access is restricted. Please check System Settings > Privacy & Security > Microphone."
        case .microphoneUnavailable:
            return "No microphone available. Please connect a microphone and try again."
        case .networkConnectionError:
            return "Network connection error. Please check your internet connection and try again."
        case .networkTimeout:
            return "Request timed out. Please check your connection and try again."
        case .transcriptionFailed(let reason):
            return reason
        case .audioProcessingError:
            return "Failed to process audio. Please try recording again."
        case .modelNotFound(let model):
            return "Model '\(model)' not found. Please download it in Settings."
        case .insufficientStorage:
            return "Insufficient storage space. Please free up some space and try again."
        case .pythonConfigurationError:
            return "Python configuration error. Please check your Python path and ensure parakeet-mlx is installed."
        case .generalError(let message):
            return message
        }
    }
    
    /// Helper to extract provider name from error message
    private static func extractProvider(from message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("openai") {
            return "OpenAI"
        } else if lowercased.contains("gemini") || lowercased.contains("google") {
            return "Gemini"
        } else if lowercased.contains("whisper") {
            return "Whisper"
        } else if lowercased.contains("parakeet") {
            return "Parakeet"
        }
        return "API"
    }
    
    /// Helper to extract model name from error message
    private static func extractModel(from message: String) -> String {
        // Try to extract model name from common patterns
        if let range = message.range(of: "model '([^']+)'", options: .regularExpression) {
            let modelPart = String(message[range])
            return modelPart.replacingOccurrences(of: "model '", with: "").replacingOccurrences(of: "'", with: "")
        }
        
        // Look for common model names
        let models = ["tiny", "base", "small", "medium", "large", "turbo"]
        let lowercased = message.lowercased()
        for model in models where lowercased.contains(model) {
            return model.capitalized
        }
        
        return "Unknown"
    }
}
