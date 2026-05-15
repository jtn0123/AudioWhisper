import SwiftUI

/// Spectrum — frequency-band visualizer, refined.
///
/// What changed vs the previous version:
/// - Replaced the 8-color rainbow with a single-hue ember-to-cream gradient
///   ramp. Adjacent bands now relate to each other instead of competing.
/// - Removed the Hz frequency labels by default. The visualizer is the point;
///   the analyzer labels were lab-equipment noise.
/// - Bars use a vertical gradient on each bar (top brighter than bottom) for
///   a hint of dimension.
/// - Peak indicator becomes a thin coral cap on top of each active bar.
struct SpectrumWaveformView: View {
    let frequencyBands: [Float]
    let isActive: Bool

    // Ember → cream gradient. Bar i picks color i.
    private let bandColors: [Color] = [
        Color(red: 0.48, green: 0.16, blue: 0.08),  // #7A2A14
        Color(red: 0.63, green: 0.23, blue: 0.11),  // #A03A1C
        Color(red: 0.76, green: 0.31, blue: 0.16),  // #C24E29
        Color(red: 0.85, green: 0.45, blue: 0.30),  // #D9734D
        Color(red: 0.91, green: 0.60, blue: 0.47),  // #E89A77
        Color(red: 0.95, green: 0.75, blue: 0.63),  // #F2BFA0
        Color(red: 0.94, green: 0.84, blue: 0.76),  // #F0D7C2
        Color(red: 0.90, green: 0.85, blue: 0.80),  // #E6D9CC
    ]

    @State private var peakLevels: [Float] = Array(repeating: 0, count: 8)
    @State private var animatedLevels: [Float] = Array(repeating: 0, count: 8)
    @State private var idlePhase: CGFloat = 0

    private let barSpacing: CGFloat = 6
    private let minHeight: CGFloat = 4
    private let cornerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let barWidth = (geometry.size.width - barSpacing * CGFloat(bandColors.count - 1)) / CGFloat(bandColors.count)
            let maxHeight = geometry.size.height - 6

            HStack(spacing: barSpacing) {
                ForEach(0..<bandColors.count, id: \.self) { index in
                    ZStack(alignment: .bottom) {
                        // Background track
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(bandColors[index].opacity(0.10))
                            .frame(width: barWidth, height: maxHeight)

                        // Active bar
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        bandColors[index],
                                        bandColors[index].opacity(0.78),
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(
                                width: barWidth,
                                height: max(minHeight, CGFloat(animatedLevels[safe: index] ?? 0) * maxHeight)
                            )

                        // Peak cap
                        if (peakLevels[safe: index] ?? 0) > 0.05 {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(bandColors[index])
                                .frame(width: barWidth, height: 2.5)
                                .offset(y: -CGFloat(peakLevels[safe: index] ?? 0) * maxHeight + 1.25)
                        }
                    }
                    .frame(height: maxHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            updateLevels()
        }
    }

    private func updateLevels() {
        idlePhase += 0.05
        for i in 0..<min(animatedLevels.count, frequencyBands.count) {
            let target: Float
            if isActive {
                target = min(1.0, frequencyBands[i] * 2.38)
            } else {
                let breathe = Float(sin(idlePhase + Double(i) * 0.3) * 0.5 + 0.5) * 0.08
                target = breathe
            }

            if target > animatedLevels[i] {
                animatedLevels[i] = target
            } else {
                animatedLevels[i] = animatedLevels[i] * 0.75 + target * 0.25
            }

            if animatedLevels[i] > peakLevels[i] {
                peakLevels[i] = animatedLevels[i]
            } else {
                peakLevels[i] = max(0, peakLevels[i] - 0.01)
            }
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}

#Preview("Spectrum · refined") {
    SpectrumWaveformView(
        frequencyBands: [0.85, 0.55, 0.7, 0.4, 0.5, 0.25, 0.3, 0.18],
        isActive: true
    )
    .frame(width: 320, height: 120)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
