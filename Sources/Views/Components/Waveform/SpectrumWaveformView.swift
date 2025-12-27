import SwiftUI

/// Frequency spectrum analyzer visualization with 8 color-coded bands.
/// Shows bass through treble frequencies with peak hold indicators.
struct SpectrumWaveformView: View {
    let frequencyBands: [Float]
    let isActive: Bool

    // Band colors (voice-optimized frequency ranges)
    private let bandColors: [Color] = [
        Color(red: 1.0, green: 0.3, blue: 0.3),   // Male fundamental - Red
        Color(red: 1.0, green: 0.5, blue: 0.2),   // Female fundamental - Orange
        Color(red: 1.0, green: 0.8, blue: 0.2),   // First formant - Yellow
        Color(red: 0.4, green: 0.9, blue: 0.3),   // Second formant - Green
        Color(red: 0.2, green: 0.9, blue: 0.8),   // Third formant - Cyan
        Color(red: 0.3, green: 0.5, blue: 1.0),   // Presence - Blue
        Color(red: 0.6, green: 0.3, blue: 1.0),   // Sibilants - Purple
        Color(red: 1.0, green: 0.4, blue: 0.8),   // Brilliance - Pink
    ]

    // Voice-optimized labels: 80Hz-1200Hz frequency markers
    private let bandLabels = ["80", "120", "180", "260", "380", "550", "750", "950"]

    @State private var peakLevels: [Float] = Array(repeating: 0, count: 8)
    @State private var animatedLevels: [Float] = Array(repeating: 0, count: 8)
    @State private var idlePhase: CGFloat = 0

    private let barSpacing: CGFloat = 6
    private let minHeight: CGFloat = 4
    private let cornerRadius: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let barWidth = (geometry.size.width - barSpacing * CGFloat(bandColors.count - 1)) / CGFloat(bandColors.count)
            let maxHeight = geometry.size.height - 20 // Leave room for labels

            HStack(spacing: barSpacing) {
                ForEach(0..<bandColors.count, id: \.self) { index in

                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            // Background bar
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(bandColors[index].opacity(0.15))
                                .frame(width: barWidth, height: maxHeight)

                            // Active bar with gradient
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            bandColors[index],
                                            bandColors[index].opacity(0.85)
                                        ],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    )
                                )
                                .frame(
                                    width: barWidth,
                                    height: max(minHeight, CGFloat(animatedLevels[safe: index] ?? 0) * maxHeight)
                                )
                                .shadow(color: bandColors[index].opacity(0.7), radius: 12, x: 0, y: 0)

                            // Peak indicator
                            if peakLevels[safe: index] ?? 0 > 0.05 {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(bandColors[index])
                                    .frame(width: barWidth, height: 3)
                                    .offset(y: -CGFloat(peakLevels[safe: index] ?? 0) * maxHeight + 1.5)
                                    .shadow(color: bandColors[index], radius: 4, x: 0, y: 0)
                            }
                        }
                        .frame(height: maxHeight)

                        // Label
                        Text(bandLabels[index])
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(bandColors[index].opacity(0.7))
                    }
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

        // Update animated levels with smoothing
        for i in 0..<min(animatedLevels.count, frequencyBands.count) {
            let target: Float
            if isActive {
                // Apply 70% gain boost (40% more than original) for reactive bars
                target = min(1.0, frequencyBands[i] * 1.7)
            } else {
                // Idle animation
                let breathe = Float(sin(idlePhase + Double(i) * 0.3) * 0.5 + 0.5) * 0.08
                target = breathe
            }

            // Smooth animation (fast attack, snappier decay)
            if target > animatedLevels[i] {
                animatedLevels[i] = target
            } else {
                animatedLevels[i] = animatedLevels[i] * 0.75 + target * 0.25
            }

            // Update peak hold
            if animatedLevels[i] > peakLevels[i] {
                peakLevels[i] = animatedLevels[i]
            } else {
                // Slow peak decay
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

#Preview("Spectrum - Active") {
    SpectrumWaveformView(
        frequencyBands: [0.8, 0.6, 0.5, 0.4, 0.3, 0.25, 0.2, 0.15],
        isActive: true
    )
    .frame(height: 120)
    .padding()
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}

#Preview("Spectrum - Idle") {
    SpectrumWaveformView(
        frequencyBands: Array(repeating: 0, count: 8),
        isActive: false
    )
    .frame(height: 120)
    .padding()
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}

// MARK: - Testable Helpers

extension SpectrumWaveformView {
    /// Applies gain boost to frequency band value (70% boost for reactive bars)
    static func testableApplyGainBoost(_ value: Float) -> Float {
        min(1.0, value * 1.7)
    }

    /// Calculates idle breathing animation value
    static func testableIdleBreathValue(phase: Double, bandIndex: Int) -> Float {
        Float(sin(phase + Double(bandIndex) * 0.3) * 0.5 + 0.5) * 0.08
    }

    /// Calculates smoothed level transition (instant attack, gradual decay)
    static func testableSmoothedLevel(current: Float, target: Float) -> Float {
        if target > current {
            return target  // Instant attack
        } else {
            return current * 0.75 + target * 0.25  // Gradual decay
        }
    }

    /// Calculates peak decay
    static func testablePeakDecay(current: Float, level: Float) -> Float {
        if level > current {
            return level  // New peak
        } else {
            return max(0, current - 0.01)  // Slow decay
        }
    }
}
