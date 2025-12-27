import SwiftUI

/// Circular/radial spectrum visualization with bars extending from center.
/// Creates a sunburst/star pattern that's visually striking.
struct CircularSpectrumView: View {
    let frequencyBands: [Float]
    let isActive: Bool

    private let barCount = 16 // Double the bands for fuller look (mirrored)

    // Neon color palette
    private let colors: [Color] = [
        Color(red: 0.0, green: 0.9, blue: 0.95),   // Cyan
        Color(red: 0.2, green: 0.9, blue: 0.6),    // Teal
        Color(red: 0.4, green: 0.9, blue: 0.3),    // Green
        Color(red: 0.8, green: 0.9, blue: 0.2),    // Yellow-green
        Color(red: 1.0, green: 0.8, blue: 0.2),    // Yellow
        Color(red: 1.0, green: 0.5, blue: 0.2),    // Orange
        Color(red: 0.95, green: 0.2, blue: 0.4),   // Red-pink
        Color(red: 0.95, green: 0.2, blue: 0.8),   // Magenta
    ]

    @State private var animatedLevels: [Float] = Array(repeating: 0.1, count: 16)
    @State private var idlePhase: CGFloat = 0
    @State private var rotationPhase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let innerRadius = size * 0.15
            let maxBarLength = size * 0.35

            ZStack {
                // Background glow
                if isActive {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [colors[4].opacity(0.2), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.5
                            )
                        )
                        .frame(width: size, height: size)
                }

                // Center circle
                Circle()
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
                    .shadow(color: colors[0].opacity(0.5), radius: 10)

                // Radial bars
                Canvas { context, canvasSize in
                    let centerPoint = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                    for i in 0..<barCount {
                        let angle = (CGFloat(i) / CGFloat(barCount)) * 2 * .pi - .pi / 2
                        let level = CGFloat(animatedLevels[i])
                        let barLength = innerRadius + (maxBarLength * level)

                        // Start and end points
                        let startX = centerPoint.x + cos(angle) * innerRadius
                        let startY = centerPoint.y + sin(angle) * innerRadius
                        let endX = centerPoint.x + cos(angle) * barLength
                        let endY = centerPoint.y + sin(angle) * barLength

                        // Color based on position
                        let colorIndex = i % colors.count
                        let barColor = colors[colorIndex]

                        // Draw glow
                        var glowPath = Path()
                        glowPath.move(to: CGPoint(x: startX, y: startY))
                        glowPath.addLine(to: CGPoint(x: endX, y: endY))

                        context.stroke(
                            glowPath,
                            with: .color(barColor.opacity(0.4)),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )

                        // Draw core bar
                        var barPath = Path()
                        barPath.move(to: CGPoint(x: startX, y: startY))
                        barPath.addLine(to: CGPoint(x: endX, y: endY))

                        context.stroke(
                            barPath,
                            with: .color(barColor),
                            style: StrokeStyle(lineWidth: 4, lineCap: .round)
                        )

                        // Draw bright tip
                        let tipPath = Path(ellipseIn: CGRect(
                            x: endX - 3,
                            y: endY - 3,
                            width: 6,
                            height: 6
                        ))
                        context.fill(tipPath, with: .color(barColor.opacity(0.9)))
                    }
                }
                .blur(radius: 1)

                // Inner ring accent
                Circle()
                    .stroke(colors[0].opacity(0.3), lineWidth: 2)
                    .frame(width: innerRadius * 2 + 4, height: innerRadius * 2 + 4)
            }
            .position(center)
        }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            updateLevels()
        }
    }

    private func updateLevels() {
        idlePhase += 0.04
        rotationPhase += 0.01

        for i in 0..<barCount {
            // Map 16 bars to 8 frequency bands (mirrored)
            let bandIndex = i < 8 ? i : (15 - i)
            let target: Float

            if isActive && bandIndex < frequencyBands.count {
                target = frequencyBands[bandIndex]
            } else {
                // Idle breathing animation
                let breathe = Float(sin(idlePhase + Double(i) * 0.4) * 0.5 + 0.5) * 0.15
                target = breathe + 0.05
            }

            // Smooth animation
            if target > animatedLevels[i] {
                animatedLevels[i] = animatedLevels[i] * 0.3 + target * 0.7
            } else {
                animatedLevels[i] = animatedLevels[i] * 0.9 + target * 0.1
            }
        }
    }
}

#Preview("Circular - Active") {
    CircularSpectrumView(
        frequencyBands: [0.8, 0.6, 0.5, 0.7, 0.4, 0.3, 0.25, 0.2],
        isActive: true
    )
    .frame(width: 200, height: 200)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}

#Preview("Circular - Idle") {
    CircularSpectrumView(
        frequencyBands: Array(repeating: 0, count: 8),
        isActive: false
    )
    .frame(width: 200, height: 200)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}

// MARK: - Testable Helpers

extension CircularSpectrumView {
    /// Maps 16 display bars to 8 frequency bands (mirrored pattern)
    static func testableBandIndex(for barIndex: Int) -> Int {
        barIndex < 8 ? barIndex : (15 - barIndex)
    }

    /// Calculates idle breathing animation value
    static func testableIdleBreathValue(phase: Double, barIndex: Int) -> Float {
        Float(sin(phase + Double(barIndex) * 0.4) * 0.5 + 0.5) * 0.15 + 0.05
    }

    /// Calculates smoothed level transition (fast attack, slow decay)
    static func testableSmoothedLevel(current: Float, target: Float) -> Float {
        if target > current {
            return current * 0.3 + target * 0.7  // Fast rise
        } else {
            return current * 0.9 + target * 0.1  // Slow decay
        }
    }
}
