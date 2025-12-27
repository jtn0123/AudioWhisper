import SwiftUI

/// Neon-style waveform visualization with glowing bezier curves and color gradients.
/// Features layered waveform trails for motion blur effect.
struct NeonWaveformView: View {
    let waveformSamples: [Float]
    let audioLevel: Float
    let isActive: Bool

    // Neon color palette
    private let cyanGlow = Color(red: 0.0, green: 0.9, blue: 0.95)
    private let magentaGlow = Color(red: 0.95, green: 0.2, blue: 0.8)
    private let yellowGlow = Color(red: 1.0, green: 0.85, blue: 0.0)
    private let bgColor = Color(red: 0.02, green: 0.02, blue: 0.04)

    // Trail history (stores previous waveform frames)
    private let trailCount = 3
    @State private var waveformHistory: [[Float]] = []
    @State private var smoothedSamples: [Float] = []
    @State private var phase: CGFloat = 0
    @State private var colorPhase: CGFloat = 0
    @State private var isViewActive = false

    // Decay factor for response speed (lower = slower, higher = snappier)
    private let decayFactor: Float = 0.55

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background glow
                if isActive && audioLevel > 0.1 {
                    backgroundGlow(in: geometry.size)
                }

                // Trail waveforms (oldest to newest, behind main)
                ForEach(0..<waveformHistory.count, id: \.self) { index in
                    let opacity = 0.15 + Double(index) * 0.1 // 0.15, 0.25, 0.35
                    let offset = CGFloat(waveformHistory.count - 1 - index) * 2 // slight vertical offset
                    trailWaveform(samples: waveformHistory[index], in: geometry.size)
                        .opacity(opacity)
                        .offset(y: offset)
                }

                // Main waveform with glow layers
                waveformStack(in: geometry.size)

                // Reflection
                waveformReflection(in: geometry.size)
            }
        }
        .onAppear {
            isViewActive = true
        }
        .onDisappear {
            isViewActive = false
        }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            guard isViewActive else { return }
            phase += 0.05
            colorPhase += 0.02
            updateSmoothedSamples()
            updateHistory()
        }
    }

    private func updateSmoothedSamples() {
        let targetSamples = rawEffectiveSamples

        // Initialize if needed
        if smoothedSamples.count != targetSamples.count {
            smoothedSamples = targetSamples
            return
        }

        // Interpolate toward target with decay for slower response
        for i in 0..<targetSamples.count {
            smoothedSamples[i] = smoothedSamples[i] * decayFactor + targetSamples[i] * (1 - decayFactor)
        }
    }

    private func updateHistory() {
        let current = smoothedSamples.isEmpty ? rawEffectiveSamples : smoothedSamples
        waveformHistory.append(current)
        if waveformHistory.count > trailCount {
            waveformHistory.removeFirst()
        }
    }

    private func trailWaveform(samples: [Float], in size: CGSize) -> some View {
        waveformPathFrom(samples: samples, in: size)
            .stroke(currentColor.opacity(0.6), lineWidth: 3)
            .blur(radius: 4)
    }

    // MARK: - Waveform Components

    private func waveformStack(in size: CGSize) -> some View {
        ZStack {
            // Outer glow (largest, most diffuse)
            waveformPath(in: size)
                .stroke(currentColor.opacity(0.45), lineWidth: 12)
                .blur(radius: 18)

            // Middle glow
            waveformPath(in: size)
                .stroke(currentColor.opacity(0.65), lineWidth: 5)
                .blur(radius: 8)

            // Inner glow
            waveformPath(in: size)
                .stroke(currentColor.opacity(0.9), lineWidth: 3)
                .blur(radius: 3)

            // Core line
            waveformPath(in: size)
                .stroke(
                    LinearGradient(
                        colors: [cyanGlow, magentaGlow, yellowGlow],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 2
                )
        }
    }

    private func waveformReflection(in size: CGSize) -> some View {
        waveformPath(in: size)
            .stroke(currentColor.opacity(0.2), lineWidth: 2)
            .blur(radius: 4)
            .scaleEffect(x: 1, y: -0.3)
            .offset(y: size.height * 0.6)
            .mask(
                LinearGradient(
                    colors: [.white.opacity(0.5), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }

    private func backgroundGlow(in size: CGSize) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [currentColor.opacity(0.35 * Double(audioLevel)), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.7
                )
            )
            .scaleEffect(1.0 + CGFloat(audioLevel) * 0.5)
            .animation(.easeOut(duration: 0.08), value: audioLevel)
    }

    // MARK: - Path Generation

    private func waveformPath(in size: CGSize) -> Path {
        waveformPathFrom(samples: effectiveSamples, in: size)
    }

    private func waveformPathFrom(samples: [Float], in size: CGSize) -> Path {
        Path { path in
            let centerY = size.height / 2
            let stepX = size.width / CGFloat(max(1, samples.count - 1))
            let maxAmplitude = size.height * 0.70

            guard !samples.isEmpty else {
                // Flat line when no samples
                path.move(to: CGPoint(x: 0, y: centerY))
                path.addLine(to: CGPoint(x: size.width, y: centerY))
                return
            }

            // Start point
            let firstY = centerY - CGFloat(samples[0]) * maxAmplitude
            path.move(to: CGPoint(x: 0, y: firstY))

            // Draw smooth bezier curve through sample points
            for i in 1..<samples.count {
                let x = CGFloat(i) * stepX
                let y = centerY - CGFloat(samples[i]) * maxAmplitude

                let prevX = CGFloat(i - 1) * stepX
                let prevY = centerY - CGFloat(samples[i - 1]) * maxAmplitude

                let controlX1 = prevX + stepX * 0.5
                let controlX2 = x - stepX * 0.5

                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: controlX1, y: prevY),
                    control2: CGPoint(x: controlX2, y: y)
                )
            }
        }
    }

    // MARK: - Computed Properties

    /// Smoothed samples for display (slower response)
    private var effectiveSamples: [Float] {
        smoothedSamples.isEmpty ? rawEffectiveSamples : smoothedSamples
    }

    /// Raw target samples before smoothing
    private var rawEffectiveSamples: [Float] {
        if isActive && !waveformSamples.isEmpty {
            // Boost samples so waveform fills out more - especially quiet signals
            return waveformSamples.map { sample in
                let sign: Float = sample >= 0 ? 1 : -1
                let magnitude = abs(sample)
                // Aggressive boost for more reactive, vibrant waveform
                let boosted = magnitude + 0.12 + magnitude * 0.6
                return sign * min(boosted, 1.0)
            }
        } else {
            // Generate idle breathing wave
            return (0..<64).map { i in
                let t = Float(i) / 64.0
                let breathe = sin(Float(phase) + t * .pi * 4) * 0.08
                return breathe
            }
        }
    }

    private var currentColor: Color {
        // Color shifts based on audio intensity
        if audioLevel > 0.7 {
            return yellowGlow
        } else if audioLevel > 0.4 {
            return magentaGlow
        } else {
            return cyanGlow
        }
    }
}

#Preview("Neon - Active") {
    NeonWaveformView(
        waveformSamples: (0..<64).map { _ in Float.random(in: -0.5...0.5) },
        audioLevel: 0.6,
        isActive: true
    )
    .frame(height: 120)
    .padding()
    .background(Color(red: 0.02, green: 0.02, blue: 0.04))
}

#Preview("Neon - Idle") {
    NeonWaveformView(
        waveformSamples: [],
        audioLevel: 0,
        isActive: false
    )
    .frame(height: 120)
    .padding()
    .background(Color(red: 0.02, green: 0.02, blue: 0.04))
}
