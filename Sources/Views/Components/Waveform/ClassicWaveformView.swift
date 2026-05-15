import SwiftUI

/// Classic level-based waveform visualization with animated bars.
/// Features gravity-based physics: bars rise quickly, fall with acceleration, and bounce.
struct ClassicWaveformView: View {
    let audioLevel: Float
    let isActive: Bool
    let barColor: Color

    private let barCount = 64
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 2

    // Physics constants
    private let gravity: CGFloat = 2.5        // Downward acceleration per frame
    private let bounceFactor: CGFloat = 0.3   // Energy retained after bounce
    private let riseSpeed: CGFloat = 0.8      // How quickly bars rise to target (0-1)

    @State private var barHeights: [CGFloat] = []
    @State private var velocities: [CGFloat] = []
    @State private var idlePhase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max(2, (geometry.size.width - totalSpacing) / CGFloat(barCount))
            let maxHeight = geometry.size.height * 0.7

            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(barColor)
                        .frame(width: barWidth, height: barHeight(for: index, maxHeight: maxHeight))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            barHeights = Array(repeating: minHeight, count: barCount)
            velocities = Array(repeating: 0, count: barCount)
        }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            updatePhysics()
        }
    }

    private func barHeight(for index: Int, maxHeight: CGFloat) -> CGFloat {
        guard index < barHeights.count else { return minHeight }
        // Scale the stored height to the current maxHeight
        return min(barHeights[index], maxHeight)
    }

    private func updatePhysics() {
        guard !barHeights.isEmpty else { return }

        // Use a reference max height for physics calculations
        let physicsMaxHeight: CGFloat = 100

        idlePhase += 0.06
        let centerIndex = barCount / 2

        for barIndex in 0..<barCount {
            let distanceFromCenter = abs(barIndex - centerIndex)
            let normalizedDistance = CGFloat(distanceFromCenter) / CGFloat(centerIndex)
            let baseShape = 1.0 - pow(normalizedDistance, 1.5)

            var targetHeight: CGFloat

            if isActive && audioLevel > 0.01 {
                // Active - calculate target based on audio level (+10% gain)
                let level = CGFloat(audioLevel) * 1.1
                let noise = CGFloat.random(in: -0.1...0.1)
                let variation = sin(CGFloat(barIndex) * 0.5 + idlePhase * 2) * 0.15
                targetHeight = minHeight + (physicsMaxHeight - minHeight) * baseShape * level * (1 + noise + variation)
                targetHeight = max(minHeight, min(physicsMaxHeight, targetHeight))
            } else {
                // Idle - subtle breathing
                let breathe = sin(idlePhase + CGFloat(barIndex) * 0.15) * 0.5 + 0.5
                targetHeight = minHeight + (physicsMaxHeight * 0.08) * baseShape * breathe
            }

            // Physics update
            if targetHeight > barHeights[barIndex] {
                // Rising: move quickly toward target (no gravity)
                barHeights[barIndex] += (targetHeight - barHeights[barIndex]) * riseSpeed
                velocities[barIndex] = 0 // Reset velocity when rising
            } else {
                // Falling: apply gravity
                velocities[barIndex] += gravity

                // Apply velocity
                barHeights[barIndex] -= velocities[barIndex]

                // Bounce off minimum height
                if barHeights[barIndex] < minHeight {
                    barHeights[barIndex] = minHeight
                    if velocities[barIndex] > 1 {
                        // Bounce with energy loss
                        velocities[barIndex] = -velocities[barIndex] * bounceFactor
                    } else {
                        velocities[barIndex] = 0
                    }
                }

                // Damping when near rest
                if abs(velocities[barIndex]) < 0.5 && abs(barHeights[barIndex] - targetHeight) < 2 {
                    velocities[barIndex] = 0
                    barHeights[barIndex] = targetHeight
                }
            }

            // Clamp height
            barHeights[barIndex] = max(minHeight, min(physicsMaxHeight, barHeights[barIndex]))
        }
    }
}

#Preview("Classic - Active") {
    ClassicWaveformView(
        audioLevel: 0.6,
        isActive: true,
        barColor: Color(red: 0.85, green: 0.83, blue: 0.80)
    )
    .frame(height: 120)
    .padding()
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}

#Preview("Classic - Idle") {
    ClassicWaveformView(
        audioLevel: 0,
        isActive: false,
        barColor: Color(red: 0.35, green: 0.34, blue: 0.33).opacity(0.5)
    )
    .frame(height: 120)
    .padding()
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
