import SwiftUI

/// Visual celebration styles for success feedback.
/// All styles use expressive animations with different celebration emphasis.
enum VisualIntensity: String, CaseIterable, Identifiable, Codable {
    case glow = "Glow"
    case balanced = "Balanced"
    case burst = "Burst"

    var id: String { rawValue }

    /// Human-readable description of the style
    var description: String {
        switch self {
        case .glow:
            return "Smooth, radiant glow effects"
        case .balanced:
            return "Mix of glow and particles"
        case .burst:
            return "Energetic particle bursts"
        }
    }

    /// Icon for the settings UI
    var icon: String {
        switch self {
        case .glow:
            return "sun.max.fill"
        case .balanced:
            return "sparkle"
        case .burst:
            return "sparkles"
        }
    }

    // MARK: - Animation Configuration

    /// Duration for state transitions (all expressive-level)
    var transitionDuration: Double { 0.35 }

    /// Spring response for bouncy animations
    var springResponse: Double { 0.4 }

    /// Spring damping fraction
    var springDamping: Double { 0.7 }

    /// Spring animation preset
    var spring: Animation {
        .spring(response: springResponse, dampingFraction: springDamping)
    }

    // MARK: - Glow Effects

    /// Multiplier for glow effect opacity/radius
    var glowIntensity: Double {
        switch self {
        case .glow: return 1.0      // Full glow emphasis
        case .balanced: return 0.6  // Moderate glow
        case .burst: return 0.3     // Subtle glow
        }
    }

    /// Number of glow pulse rings
    var glowRingCount: Int {
        switch self {
        case .glow: return 3        // Multiple glow rings
        case .balanced: return 1    // Single glow ring
        case .burst: return 0       // No glow rings
        }
    }

    /// Glow pulse duration
    var glowDuration: Double {
        switch self {
        case .glow: return 0.8      // Slower, more dramatic
        case .balanced: return 0.5  // Medium
        case .burst: return 0.3     // Quick
        }
    }

    // MARK: - Particle Effects

    /// Multiplier for particle counts in neon waveform
    var particleMultiplier: Double {
        switch self {
        case .glow: return 0.5      // Fewer background particles
        case .balanced: return 1.0  // Normal particles
        case .burst: return 1.5     // More particles
        }
    }

    /// Number of confetti particles for success celebration
    var confettiCount: Int {
        switch self {
        case .glow: return 0        // No confetti
        case .balanced: return 12   // Moderate confetti
        case .burst: return 30      // Lots of confetti
        }
    }

    /// Number of expanding rings for success celebration
    var ringCount: Int {
        switch self {
        case .glow: return 2        // Glow rings
        case .balanced: return 1    // Single ring
        case .burst: return 0       // No rings, just particles
        }
    }

    /// Confetti particle size range
    var confettiSizeRange: ClosedRange<CGFloat> {
        switch self {
        case .glow: return 4...8
        case .balanced: return 6...12
        case .burst: return 8...16  // Larger particles
        }
    }

    /// Confetti burst speed
    var confettiBurstSpeed: ClosedRange<Double> {
        switch self {
        case .glow: return 1...3
        case .balanced: return 2...5
        case .burst: return 3...7   // Faster burst
        }
    }

    // MARK: - Flash Effects

    /// Whether to show flash overlay on success
    var showFlash: Bool {
        self == .burst  // Only burst has flash
    }

    /// Flash opacity
    var flashOpacity: Double {
        switch self {
        case .glow: return 0
        case .balanced: return 0
        case .burst: return 0.3
        }
    }

    // MARK: - Glass Background

    /// Whether to show glass background effect (all styles use glass)
    var showGlass: Bool { true }

    // MARK: - Entry Animation

    /// Scale factor for entry animation start
    var entryScale: CGFloat { 0.9 }

    /// Rotation for entry animation
    var entryRotation: Double { 0 }

    // MARK: - Status Dot Enhancement

    /// Whether to add glow to status dot (all styles use glow)
    var dotGlow: Bool { true }

    /// Status dot glow radius
    var dotGlowRadius: CGFloat {
        switch self {
        case .glow: return 8        // Larger glow
        case .balanced: return 5    // Medium glow
        case .burst: return 3       // Smaller glow
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
                return .balanced // Default to balanced
            }
            return intensity
        }
        set {
            set(newValue.rawValue, forKey: Self.visualIntensityKey)
        }
    }
}
