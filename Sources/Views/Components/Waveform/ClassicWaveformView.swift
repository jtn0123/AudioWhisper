import SwiftUI

/// Classic level-based waveform visualization with 48 animated bars.
/// This is the original visualization style, driven by audio level (not raw samples).
struct ClassicWaveformView: View {
    let audioLevel: Float
    let isActive: Bool
    let barColor: Color

    private let barCount = 48
    private let barWidth: CGFloat = 2
    private let barSpacing: CGFloat = 2
    private let minHeight: CGFloat = 2
    private let maxHeight: CGFloat = 60

    @State private var animatedLevels: [CGFloat] = []
    @State private var idlePhase: CGFloat = 0

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(barColor)
                    .frame(width: barWidth, height: barHeight(for: index))
            }
        }
        .onAppear {
            animatedLevels = Array(repeating: minHeight, count: barCount)
        }
        .onReceive(Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()) { _ in
            updateLevels()
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard index < animatedLevels.count else { return minHeight }
        return animatedLevels[index]
    }

    private func updateLevels() {
        idlePhase += 0.08

        var newLevels: [CGFloat] = []
        let centerIndex = barCount / 2

        for i in 0..<barCount {
            let distanceFromCenter = abs(i - centerIndex)
            let normalizedDistance = CGFloat(distanceFromCenter) / CGFloat(centerIndex)

            // Base wave shape - higher in center, tapering to edges
            let baseShape = 1.0 - pow(normalizedDistance, 1.5)

            if isActive && audioLevel > 0.01 {
                // Active recording - respond to audio
                let level = CGFloat(audioLevel)

                // Add some randomness for organic feel
                let noise = CGFloat.random(in: -0.15...0.15)
                let variation = sin(CGFloat(i) * 0.5 + idlePhase * 2) * 0.2

                let height = minHeight + (maxHeight - minHeight) * baseShape * level * (1 + noise + variation)
                newLevels.append(max(minHeight, min(maxHeight, height)))
            } else {
                // Idle state - subtle breathing wave
                let breathe = sin(idlePhase + CGFloat(i) * 0.15) * 0.5 + 0.5
                let idleHeight = minHeight + (maxHeight * 0.08) * baseShape * breathe
                newLevels.append(idleHeight)
            }
        }

        // Smooth transition
        withAnimation(.linear(duration: 0.05)) {
            animatedLevels = newLevels
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
