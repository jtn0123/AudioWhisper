import SwiftUI

/// Neon-style waveform visualization with glowing bezier curves and color gradients.
/// Uses real audio samples for accurate waveform representation.
struct NeonWaveformView: View {
    let waveformSamples: [Float]
    let audioLevel: Float
    let isActive: Bool

    // Neon color palette
    private let cyanGlow = Color(red: 0.0, green: 0.9, blue: 0.95)
    private let magentaGlow = Color(red: 0.95, green: 0.2, blue: 0.8)
    private let yellowGlow = Color(red: 1.0, green: 0.85, blue: 0.0)
    private let bgColor = Color(red: 0.02, green: 0.02, blue: 0.04)

    @State private var phase: CGFloat = 0
    @State private var colorPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background glow
                if isActive && audioLevel > 0.1 {
                    backgroundGlow(in: geometry.size)
                }

                // Main waveform with glow layers
                waveformStack(in: geometry.size)

                // Reflection
                waveformReflection(in: geometry.size)
            }
        }
        .onReceive(Timer.publish(every: 0.016, on: .main, in: .common).autoconnect()) { _ in
            phase += 0.05
            colorPhase += 0.02
        }
    }

    // MARK: - Waveform Components

    private func waveformStack(in size: CGSize) -> some View {
        ZStack {
            // Outer glow (largest, most diffuse)
            waveformPath(in: size)
                .stroke(currentColor.opacity(0.3), lineWidth: 8)
                .blur(radius: 12)

            // Middle glow
            waveformPath(in: size)
                .stroke(currentColor.opacity(0.5), lineWidth: 4)
                .blur(radius: 6)

            // Inner glow
            waveformPath(in: size)
                .stroke(currentColor.opacity(0.8), lineWidth: 2)
                .blur(radius: 2)

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
                    colors: [currentColor.opacity(0.2 * Double(audioLevel)), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size.width * 0.6
                )
            )
            .scaleEffect(1.0 + CGFloat(audioLevel) * 0.3)
            .animation(.easeOut(duration: 0.1), value: audioLevel)
    }

    // MARK: - Path Generation

    private func waveformPath(in size: CGSize) -> Path {
        Path { path in
            let centerY = size.height / 2
            let samples = effectiveSamples
            let stepX = size.width / CGFloat(max(1, samples.count - 1))
            let maxAmplitude = size.height * 0.4

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

    private var effectiveSamples: [Float] {
        if isActive && !waveformSamples.isEmpty {
            return waveformSamples
        } else {
            // Generate idle breathing wave
            return (0..<64).map { i in
                let t = Float(i) / 64.0
                let breathe = sin(Float(phase) + t * .pi * 4) * 0.05
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
