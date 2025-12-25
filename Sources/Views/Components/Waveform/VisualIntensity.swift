import SwiftUI

/// Visual intensity levels for UI effects and animations.
/// Controls the prominence of celebrations, transitions, and glass effects.
enum VisualIntensity: String, CaseIterable, Identifiable, Codable {
    case subtle = "Subtle"
    case expressive = "Expressive"
    case bold = "Bold"

    var id: String { rawValue }

    /// Human-readable description of the intensity
    var description: String {
        switch self {
        case .subtle:
            return "Elegant micro-interactions"
        case .expressive:
            return "Satisfying feedback animations"
        case .bold:
            return "Eye-catching celebrations"
        }
    }

    /// Icon for the settings UI
    var icon: String {
        switch self {
        case .subtle:
            return "circle"
        case .expressive:
            return "circle.inset.filled"
        case .bold:
            return "sparkles"
        }
    }

    // MARK: - Animation Configuration

    /// Duration for state transitions
    var transitionDuration: Double {
        switch self {
        case .subtle: return 0.2
        case .expressive: return 0.35
        case .bold: return 0.5
        }
    }

    /// Spring response for bouncy animations
    var springResponse: Double {
        switch self {
        case .subtle: return 0.3
        case .expressive: return 0.4
        case .bold: return 0.5
        }
    }

    /// Spring damping fraction
    var springDamping: Double {
        switch self {
        case .subtle: return 0.9
        case .expressive: return 0.7
        case .bold: return 0.6
        }
    }

    /// Spring animation preset
    var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    // MARK: - Effect Intensity

    /// Multiplier for glow effect opacity/radius
    var glowIntensity: Double {
        switch self {
        case .subtle: return 0.3
        case .expressive: return 0.6
        case .bold: return 1.0
        }
    }

    /// Multiplier for particle counts
    var particleMultiplier: Double {
        switch self {
        case .subtle: return 0.5
        case .expressive: return 1.0
        case .bold: return 1.5
        }
    }

    /// Number of confetti particles for success celebration
    var confettiCount: Int {
        switch self {
        case .subtle: return 0
        case .expressive: return 10
        case .bold: return 25
        }
    }

    /// Number of expanding rings for success celebration
    var ringCount: Int {
        switch self {
        case .subtle: return 0
        case .expressive: return 1
        case .bold: return 3
        }
    }

    /// Whether to show flash overlay on success
    var showFlash: Bool {
        self == .bold
    }

    /// Whether to show glass background effect
    var showGlass: Bool {
        self != .subtle
    }

    // MARK: - Entry Animation

    /// Scale factor for entry animation start
    var entryScale: CGFloat {
        switch self {
        case .subtle: return 0.95
        case .expressive: return 0.9
        case .bold: return 0.85
        }
    }

    /// Rotation for entry animation (bold only)
    var entryRotation: Double {
        switch self {
        case .subtle: return 0
        case .expressive: return 0
        case .bold: return 2
        }
    }

    // MARK: - Status Dot Enhancement

    /// Whether to add glow to status dot
    var dotGlow: Bool {
        self != .subtle
    }

    /// Status dot glow radius
    var dotGlowRadius: CGFloat {
        switch self {
        case .subtle: return 0
        case .expressive: return 4
        case .bold: return 8
        }
    }
}

// MARK: - UserDefaults Extension

extension UserDefaults {
    private static let visualIntensityKey = "visualIntensity"

    var visualIntensity: VisualIntensity {
        get {
            guard let rawValue = string(forKey: Self.visualIntensityKey),
                  let intensity = VisualIntensity(rawValue: rawValue) else {
                return .expressive // Default to expressive
            }
            return intensity
        }
        set {
            set(newValue.rawValue, forKey: Self.visualIntensityKey)
        }
    }
}
