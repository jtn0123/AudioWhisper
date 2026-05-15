import SwiftUI

/// Neon waveform — refined to lock to the AW coral palette.
///
/// What changed vs the previous version:
/// - Dropped the cyan / magenta / yellow color cycling. The waveform now
///   uses one coral palette across all audio levels.
/// - Glow intensity (line width + opacity) scales with audio level instead
///   of changing hue. Reads as "the sound got louder" not "the slot machine
///   landed on yellow."
/// - Core gradient stroke goes from coral-deep through coral to coral-lite,
///   so the curve still feels three-dimensional but in one hue family.
struct NeonWaveformView: View {
    let waveformSamples: [Float]
    let audioLevel: Float
    let isActive: Bool

    // AW coral palette
    private let coralDeep = Color(red: 0.70, green: 0.34, blue: 0.23)
    private let coral     = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let coralLite = Color(red: 0.91, green: 0.60, blue: 0.47)

    private let trailCount = 3
    @State private var waveformHistory: [[Float]] = []
    @State private var smoothedSamples: [Float] = []
    @State private var phase: CGFloat = 0
    @State private var isViewActive = false

    private let decayFactor: Float = 0.55

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isActive && audioLevel > 0.1 {
                    backgroundGlow(in: geometry.size)
                }

                ForEach(0..<waveformHistory.count, id: \.self) { index in
                    let opacity = 0.12 + Double(index) * 0.08
                    let offset = CGFloat(waveformHistory.count - 1 - index) * 2
                    trailWaveform(samples: waveformHistory[index], in: geometry.size)
                        .opacity(opacity)
                        .offset(y: offset)
                }

                waveformStack(in: geometry.size)

                waveformReflection(in: geometry.size)
            }
        }
        .onAppear { isViewActive = true }
        .onDisappear { isViewActive = false }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            guard isViewActive else { return }
            phase += 0.05
            updateSmoothedSamples()
            updateHistory()
        }
    }

    // MARK: - Layers

    private func waveformStack(in size: CGSize) -> some View {
        let glowAlpha = 0.30 + Double(audioLevel) * 0.40
        let coreWidth = 1.5 + CGFloat(audioLevel) * 1.0
        return ZStack {
            // Outer glow
            waveformPath(in: size)
                .stroke(coral.opacity(glowAlpha), lineWidth: 14)
                .blur(radius: 16)

            waveformPath(in: size)
                .stroke(coral.opacity(glowAlpha + 0.2), lineWidth: 5)
                .blur(radius: 6)

            waveformPath(in: size)
                .stroke(coral.opacity(0.9), lineWidth: 2)
                .blur(radius: 2)

            // Core gradient line
            waveformPath(in: size)
                .stroke(
                    LinearGradient(
                        colors: [coralDeep, coral, coralLite],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: coreWidth, lineCap: .round)
                )
        }
    }

    private func trailWaveform(samples: [Float], in size: CGSize) -> some View {
        waveformPathFrom(samples: samples, in: size)
            .stroke(coral.opacity(0.45), lineWidth: 3)
            .blur(radius: 4)
    }

    private func waveformReflection(in size: CGSize) -> some View {
        waveformPath(in: size)
            .stroke(coralLite.opacity(0.18), lineWidth: 2)
            .blur(radius: 4)
            .scaleEffect(x: 1, y: -0.3)
            .offset(y: size.height * 0.6)
            .mask(
                LinearGradient(
                    colors: [.white.opacity(0.5), .clear],
                    startPoint: .top, endPoint: .bottom
                )
            )
    }

    private func backgroundGlow(in size: CGSize) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [coral.opacity(0.35 * Double(audioLevel)), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.7
                )
            )
            .scaleEffect(1.0 + CGFloat(audioLevel) * 0.5)
            .animation(.easeOut(duration: 0.08), value: audioLevel)
    }

    // MARK: - Sample handling (unchanged)

    private func updateSmoothedSamples() {
        let target = rawEffectiveSamples
        if smoothedSamples.count != target.count {
            smoothedSamples = target
            return
        }
        for i in 0..<target.count {
            smoothedSamples[i] = smoothedSamples[i] * decayFactor + target[i] * (1 - decayFactor)
        }
    }

    private func updateHistory() {
        let current = smoothedSamples.isEmpty ? rawEffectiveSamples : smoothedSamples
        waveformHistory.append(current)
        if waveformHistory.count > trailCount {
            waveformHistory.removeFirst()
        }
    }

    private func waveformPath(in size: CGSize) -> Path {
        waveformPathFrom(samples: effectiveSamples, in: size)
    }

    private func waveformPathFrom(samples: [Float], in size: CGSize) -> Path {
        Path { path in
            let centerY = size.height / 2
            let stepX = size.width / CGFloat(max(1, samples.count - 1))
            let maxAmp = size.height * 0.70

            guard !samples.isEmpty else {
                path.move(to: CGPoint(x: 0, y: centerY))
                path.addLine(to: CGPoint(x: size.width, y: centerY))
                return
            }

            let firstY = centerY - CGFloat(samples[0]) * maxAmp
            path.move(to: CGPoint(x: 0, y: firstY))

            for i in 1..<samples.count {
                let x = CGFloat(i) * stepX
                let y = centerY - CGFloat(samples[i]) * maxAmp
                let prevX = CGFloat(i - 1) * stepX
                let prevY = centerY - CGFloat(samples[i - 1]) * maxAmp
                let c1x = prevX + stepX * 0.5
                let c2x = x - stepX * 0.5
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: c1x, y: prevY),
                    control2: CGPoint(x: c2x, y: y)
                )
            }
        }
    }

    private var effectiveSamples: [Float] {
        smoothedSamples.isEmpty ? rawEffectiveSamples : smoothedSamples
    }

    private var rawEffectiveSamples: [Float] {
        if isActive && !waveformSamples.isEmpty {
            return waveformSamples.map { s in
                let sign: Float = s >= 0 ? 1 : -1
                let mag = abs(s)
                let boosted = mag + 0.12 + mag * 0.6
                return sign * min(boosted, 1.0)
            }
        } else {
            return (0..<64).map { i in
                let t = Float(i) / 64.0
                return sin(Float(phase) + t * .pi * 4) * 0.08
            }
        }
    }
}

#Preview("Neon · refined") {
    NeonWaveformView(
        waveformSamples: (0..<64).map { _ in Float.random(in: -0.5...0.5) },
        audioLevel: 0.6,
        isActive: true
    )
    .frame(width: 320, height: 140)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
