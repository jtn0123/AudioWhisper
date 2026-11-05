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
        // mountains have settled onto the horizon. `settled` is observed, so
        // the body re-runs (and pauses) when it flips. 60 fps is plenty for
        // this motion and halves the work on a 120 Hz display.
        let schedule = AnimationTimelineSchedule.animation(
            minimumInterval: Self.frameInterval, paused: Self.paused(isActive: isActive, engine: engine))
        return TimelineView(schedule) { timeline in
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

    static let frameInterval = 1.0 / 60

    static func paused(isActive: Bool, engine: AuroraEngine) -> Bool { !isActive && engine.settled }
}
