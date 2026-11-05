import Foundation

/// Available waveform visualization styles.
///
/// Neon Dusk, Molten and Electric are the Aurora styles: three overlapping
/// mountains, each in its own hue, with colour that crawls left → right. Their
/// silhouette is a separate setting (`AppDefaults.auroraShape`).
///
/// What changed: the three "current" styles (Classic, Neon, Spectrum) are
/// kept but their palettes are refined. The three older "decorative" styles
/// (Circular, Pulse Rings, Particles) are replaced by five new ones that all
/// share the app's coral/cream/sage palette:
///   - Stream (was Particles): particles flow horizontally — voice as wind
///   - Constellation: drifting nodes with proximity-based connections
///   - Halo (was Circular): rotating gradient ring
///   - Dial: Apple Watch energy dial with peripheral ticks
///   - Heartbeat (was Pulse Rings): one dominant ring per peak
enum WaveformStyle: String, CaseIterable, Identifiable, Codable {
    case classic       = "Classic"
    case neon          = "Neon"
    case spectrum      = "Spectrum"
    case stream        = "Stream"
    case constellation = "Constellation"
    case halo          = "Halo"
    case dial          = "Dial"
    case heartbeat     = "Heartbeat"
    case neonDusk      = "Neon Dusk"
    case molten        = "Molten"
    case electric      = "Electric"

    var id: String { rawValue }

    /// Human-readable description for the picker.
    var description: String {
        switch self {
        case .classic:       return "Bouncing bars"
        case .neon:          return "Glowing curve + trails"
        case .spectrum:      return "Frequency bands"
        case .stream:        return "Particles flowing"
        case .constellation: return "Drifting network"
        case .halo:          return "Rotating gradient ring"
        case .dial:          return "Audio energy dial"
        case .heartbeat:     return "Dramatic single rings"
        case .neonDusk:      return "Cyan, magenta and amber mountains"
        case .molten:        return "Gold, rose and violet mountains"
        case .electric:      return "Teal, blue and magenta mountains"
        }
    }

    /// Whether the visualization is intrinsically square (otherwise it's a
    /// horizontal strip). Used by the picker to size preview tiles.
    var isRadial: Bool {
        switch self {
        case .halo, .dial, .heartbeat: return true
        default: return false
        }
    }

    /// Whether this style requires raw samples / FFT bands. Classic and
    /// Heartbeat use only the smoothed `audioLevel`.
    var requiresEnhancedAudio: Bool {
        switch self {
        case .classic, .heartbeat: return false
        default: return true
        }
    }

    /// Styles introduced in this redesign — used by the picker to show a
    /// small "NEW" badge.
    var isNew: Bool {
        switch self {
        case .stream, .constellation, .halo, .dial, .heartbeat,
             .neonDusk, .molten, .electric: return true
        default: return false
        }
    }

    /// The Aurora palette for the three multi-hue mountain styles; nil otherwise.
    /// These styles also follow the Aurora shape setting (Horizon or Lens).
    var auroraPalette: AuroraPalette? {
        switch self {
        case .neonDusk: return .neonDusk
        case .molten: return .molten
        case .electric: return .electric
        default: return nil
        }
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
