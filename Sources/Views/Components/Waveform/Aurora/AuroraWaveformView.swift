import SwiftUI

/// Aurora waveform: three overlapping mountains, each in its own hue, with a
/// colour field that crawls left → right (slowly at rest, faster with voice).
/// Used by the Neon Dusk, Molten and Electric styles; the silhouette comes from
/// the user's Aurora shape setting.
struct AuroraWaveformView: View {
    let palette: AuroraPalette
    let waveformSamples: [Float]
    let audioLevel: Float
    let isActive: Bool
    /// Explicit shape for previews/tests; nil follows the user's setting.
    var shape: AuroraShape?

    @AppDefault(\.auroraShape) private var storedShape
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var engine = AuroraEngine()

    var body: some View {
        // Keep ticking while recording, and afterwards only until the
        // mountains have settled onto the horizon.
        TimelineView(.animation(paused: !isActive && engine.isAtRest)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                engine.advance(to: time, rawLevel: isActive ? audioLevel : 0,
                               samples: isActive ? waveformSamples : [], reduceMotion: reduceMotion)
                AuroraRenderer.draw(shape ?? storedShape, palette: palette, engine: engine,
                                    in: &context, size: size)
            }
        }
        .accessibilityHidden(true)
    }
}
