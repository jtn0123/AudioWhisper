import SwiftUI

/// Linear-ish sRGB triple used by the Aurora renderer. Kept as plain doubles so
/// the per-frame colour field can be interpolated without going through `Color`.
struct AuroraRGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    func color(_ alpha: Double = 1) -> Color {
        Color(red: red, green: green, blue: blue).opacity(alpha)
    }

    func lerp(_ other: AuroraRGB, _ amount: Double) -> AuroraRGB {
        AuroraRGB(red + (other.red - red) * amount,
                  green + (other.green - green) * amount,
                  blue + (other.blue - blue) * amount)
    }
}

/// One Aurora colour scene. Five bright crest stops and five deeper, hue-shifted
/// body stops. Each mountain owns its own slice of the stops (see
/// `AuroraRenderer.lobeBands`), so the three mountains always read as three hues.
struct AuroraPalette: Equatable {
    let crest: [AuroraRGB]
    let deep: [AuroraRGB]

    /// Electric's cyan → violet → magenta running into Molten's rose → amber.
    static let neonDusk = AuroraPalette(
        crest: [AuroraRGB(0.00, 0.90, 1.00), AuroraRGB(0.46, 0.38, 1.00), AuroraRGB(1.00, 0.24, 0.80),
                AuroraRGB(1.00, 0.26, 0.46), AuroraRGB(1.00, 0.64, 0.12)],
        deep: [AuroraRGB(0.00, 0.46, 1.00), AuroraRGB(0.32, 0.10, 1.00), AuroraRGB(0.84, 0.04, 0.60),
               AuroraRGB(0.90, 0.06, 0.30), AuroraRGB(0.98, 0.30, 0.06)])

    /// Sunset gold and amber melting into rose, magenta and violet.
    static let molten = AuroraPalette(
        crest: [AuroraRGB(1.00, 0.78, 0.22), AuroraRGB(1.00, 0.58, 0.10), AuroraRGB(1.00, 0.34, 0.40),
                AuroraRGB(1.00, 0.26, 0.74), AuroraRGB(0.70, 0.30, 1.00)],
        deep: [AuroraRGB(1.00, 0.36, 0.06), AuroraRGB(0.96, 0.10, 0.30), AuroraRGB(0.86, 0.06, 0.46),
               AuroraRGB(0.56, 0.10, 0.96), AuroraRGB(0.30, 0.10, 0.90)])

    /// Teal and cyan through ultramarine and violet to magenta.
    static let electric = AuroraPalette(
        crest: [AuroraRGB(0.10, 1.00, 0.80), AuroraRGB(0.00, 0.86, 1.00), AuroraRGB(0.30, 0.50, 1.00),
                AuroraRGB(0.62, 0.32, 1.00), AuroraRGB(1.00, 0.24, 0.84)],
        deep: [AuroraRGB(0.00, 0.56, 0.80), AuroraRGB(0.00, 0.40, 1.00), AuroraRGB(0.24, 0.12, 1.00),
               AuroraRGB(0.50, 0.06, 0.96), AuroraRGB(0.86, 0.04, 0.60)])

    /// Cosine-eased sample at a fractional stop index (clamped to the stops).
    static func sample(_ stops: [AuroraRGB], at position: Double) -> AuroraRGB {
        let clamped = min(Double(stops.count - 1), max(0, position))
        let index = min(stops.count - 2, Int(clamped))
        let eased = (1 - cos((clamped - Double(index)) * .pi)) / 2
        return stops[index].lerp(stops[index + 1], eased)
    }
}

/// Silhouette used by the three Aurora styles.
enum AuroraShape: String, CaseIterable, Identifiable, Codable {
    /// Mountains rise off a glowing horizon with a short reflection below.
    case horizon = "Horizon"
    /// Mirrored glass lenses above and below a centre line.
    case lens = "Lens"

    var id: String { rawValue }
}
