import Foundation

/// Available waveform visualization styles
enum WaveformStyle: String, CaseIterable, Identifiable, Codable {
    case classic = "Classic"
    case neon = "Neon"
    case spectrum = "Spectrum"

    var id: String { rawValue }

    /// Human-readable description of the style
    var description: String {
        switch self {
        case .classic:
            return "Simple animated bars"
        case .neon:
            return "Glowing waveform with particles"
        case .spectrum:
            return "Frequency spectrum analyzer"
        }
    }

    /// Whether this style requires enhanced audio data (raw samples, FFT)
    var requiresEnhancedAudio: Bool {
        self != .classic
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    private static let waveformStyleKey = "waveformStyle"

    var waveformStyle: WaveformStyle {
        get {
            guard let rawValue = string(forKey: Self.waveformStyleKey),
                  let style = WaveformStyle(rawValue: rawValue) else {
                return .classic
            }
            return style
        }
        set {
            set(newValue.rawValue, forKey: Self.waveformStyleKey)
        }
    }
}
