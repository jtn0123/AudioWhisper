import Foundation

/// Available waveform visualization styles
enum WaveformStyle: String, CaseIterable, Identifiable, Codable {
    case classic = "Classic"
    case neon = "Neon"
    case spectrum = "Spectrum"
    case circular = "Circular"
    case pulseRings = "Pulse Rings"
    case particles = "Particles"

    var id: String { rawValue }

    /// Human-readable description of the style
    var description: String {
        switch self {
        case .classic:
            return "Bouncing bars with gravity"
        case .neon:
            return "Glowing waveform with trails"
        case .spectrum:
            return "Voice frequency analyzer"
        case .circular:
            return "Radial sunburst pattern"
        case .pulseRings:
            return "Expanding ripple rings"
        case .particles:
            return "Floating particle field"
        }
    }

    /// Whether this style requires enhanced audio data (raw samples, FFT)
    var requiresEnhancedAudio: Bool {
        self != .classic && self != .pulseRings
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
