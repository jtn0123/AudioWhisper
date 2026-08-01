import Foundation

internal enum WhisperModelError: Error, LocalizedError, Sendable {
    case invalidURL(fileName: String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL(let fileName):
            return "Invalid URL for whisper model file: \(fileName)"
        }
    }
}

internal enum TranscriptionProvider: String, CaseIterable, Codable, Sendable {
    case local
    case parakeet

    var displayName: String {
        switch self {
        case .local:
            return "Local Whisper"
        case .parakeet:
            return "Parakeet (Advanced)"
        }
    }
}

internal enum WhisperModel: String, CaseIterable, Codable, Sendable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"
    case largeTurbo = "large-v3-turbo"

    var displayName: String {
        switch self {
        case .tiny:
            return "Tiny (39MB)"
        case .base:
            return "Base (142MB)"
        case .small:
            return "Small (466MB)"
        case .largeTurbo:
            return "Large Turbo (1.5GB)"
        }
    }

    var fileSize: String {
        switch self {
        case .tiny:
            return "39MB"
        case .base:
            return "142MB"
        case .small:
            return "466MB"
        case .largeTurbo:
            return "1.5GB"
        }
    }

    var fileName: String {
        return "ggml-\(rawValue).bin"
    }

    var downloadURL: URL {
        // Safe fallback version - returns base model URL if current model URL is invalid
        // Note: These URLs are hardcoded constants and should never fail to parse,
        // but we handle it gracefully without force unwrapping for safety.
        do {
            return try getDownloadURL()
        } catch {
            // Fallback to base model if there's an issue with the current model URL
            // Use a known-good hardcoded URL that will always parse successfully
            return URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!
        }
    }

    func getDownloadURL() throws -> URL {
        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)") else {
            throw WhisperModelError.invalidURL(fileName: fileName)
        }
        return url
    }

    var description: String {
        switch self {
        case .tiny:
            return "Fastest, basic accuracy"
        case .base:
            return "Good balance of speed and accuracy"
        case .small:
            return "Better accuracy, reasonable speed"
        case .largeTurbo:
            return "Highest accuracy, optimized for speed"
        }
    }
}

/// Speech-to-text models available through Parakeet-MLX.
///
/// Ordered smallest → largest, which is also the order the picker renders.
/// Every case must be loadable by `parakeet_mlx.from_pretrained`; that library
/// dispatches on the `target` field of the model's `config.json` and, as of
/// parakeet-mlx 0.5.2, supports `EncDecRNNTBPEModel`,
/// `EncDecHybridRNNTCTCBPEModel` and `EncDecCTCModelBPE`. Models published for
/// the separate `mlx-audio` runtime (Qwen3-ASR, Nemotron streaming, Voxtral,
/// Granite Speech) are NOT drop-in and would need new Python integration.
///
/// WER figures below are the published Open ASR Leaderboard averages — lower is
/// better. They are the reason `v2English` is described as the accurate English
/// choice: multilingual v3 trades ~0.3 WER for 25-language coverage.
internal enum ParakeetModel: String, CaseIterable, Codable, Sendable {
    /// 110M-parameter hybrid TDT/CTC. 5.5× smaller than the 0.6B models for
    /// roughly 1.2 WER points. Still emits punctuation and capitalisation.
    case tdtCtc110mEnglish = "mlx-community/parakeet-tdt_ctc-110m"
    case v2English = "mlx-community/parakeet-tdt-0.6b-v2"
    case v3Multilingual = "mlx-community/parakeet-tdt-0.6b-v3"

    var displayName: String {
        switch self {
        case .tdtCtc110mEnglish:
            return "110M English (~0.5 GB)"
        case .v2English:
            return "v2 English (~2.5 GB)"
        case .v3Multilingual:
            return "v3 Multilingual (~2.5 GB)"
        }
    }

    var description: String {
        switch self {
        case .tdtCtc110mEnglish:
            return "Lightest — 5× smaller, slightly less accurate (7.5% WER)"
        case .v2English:
            return "Most accurate for English (6.1% WER)"
        case .v3Multilingual:
            return "25 languages with auto-detection (6.3% WER)"
        }
    }

    var repoId: String {
        rawValue
    }
}
