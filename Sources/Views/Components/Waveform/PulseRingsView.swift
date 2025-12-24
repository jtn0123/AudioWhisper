import SwiftUI

/// Pulse rings visualization - concentric rings expand outward on audio peaks.
/// Creates a ripple-in-water effect that's very satisfying for voice/speech.
struct PulseRingsView: View {
    let audioLevel: Float
    let isActive: Bool

    // Ring tracking
    @State private var rings: [Ring] = []
    @State private var lastPeakTime: Date = .distantPast
    @State private var idlePhase: CGFloat = 0

    // Colors
    private let primaryColor = Color(red: 0.0, green: 0.9, blue: 0.95)
    private let secondaryColor = Color(red: 0.95, green: 0.2, blue: 0.8)
    private let accentColor = Color(red: 1.0, green: 0.85, blue: 0.0)

    private let maxRings = 8
    private let ringLifetime: TimeInterval = 1.5
    private let peakThreshold: Float = 0.15
    private let peakCooldown: TimeInterval = 0.1

    struct Ring: Identifiable {
        let id = UUID()
        var radius: CGFloat
        var opacity: CGFloat
        var color: Color
        let createdAt: Date
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // Background pulse glow
                if isActive && audioLevel > 0.1 {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [currentColor.opacity(0.15 * Double(audioLevel)), .clear],
                                center: .center,
                                startRadius: 0,
                                endRadius: size * 0.5
                            )
                        )
                        .scaleEffect(1.0 + CGFloat(audioLevel) * 0.2)
                }

                // Expanding rings
                ForEach(rings) { ring in
                    Circle()
                        .stroke(ring.color.opacity(ring.opacity), lineWidth: 3)
                        .frame(width: ring.radius * 2, height: ring.radius * 2)
                        .blur(radius: 2)

                    // Inner glow ring
                    Circle()
                        .stroke(ring.color.opacity(ring.opacity * 0.5), lineWidth: 6)
                        .frame(width: ring.radius * 2, height: ring.radius * 2)
                        .blur(radius: 6)
                }

                // Center orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                currentColor.opacity(0.8),
                                currentColor.opacity(0.4),
                                currentColor.opacity(0.1)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: size * 0.1
                        )
                    )
                    .frame(width: size * 0.15, height: size * 0.15)
                    .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.3 : 0.8 + sin(idlePhase) * 0.1)
                    .shadow(color: currentColor.opacity(0.6), radius: 10)

                // Idle breathing ring
                if !isActive {
                    Circle()
                        .stroke(primaryColor.opacity(0.2), lineWidth: 2)
                        .frame(width: size * 0.4 + sin(idlePhase) * 10, height: size * 0.4 + sin(idlePhase) * 10)
                }
            }
            .position(center)
        }
        .onReceive(Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()) { _ in
            updateRings()
        }
    }

    private var currentColor: Color {
        if audioLevel > 0.7 {
            return accentColor
        } else if audioLevel > 0.4 {
            return secondaryColor
        } else {
            return primaryColor
        }
    }

    private func updateRings() {
        idlePhase += 0.05

        let now = Date()

        // Check for peak to spawn new ring
        if isActive && audioLevel > peakThreshold {
            if now.timeIntervalSince(lastPeakTime) > peakCooldown {
                spawnRing()
                lastPeakTime = now
            }
        }

        // Update existing rings
        rings = rings.compactMap { ring in
            let age = now.timeIntervalSince(ring.createdAt)
            if age > ringLifetime {
                return nil
            }

            var updatedRing = ring
            let progress = age / ringLifetime

            // Expand radius over time
            updatedRing.radius = 20 + CGFloat(progress) * 100

            // Fade out as ring expands
            updatedRing.opacity = CGFloat(1.0 - progress) * 0.8

            return updatedRing
        }
    }

    private func spawnRing() {
        guard rings.count < maxRings else { return }

        let newRing = Ring(
            radius: 20,
            opacity: 0.8,
            color: currentColor,
            createdAt: Date()
        )
        rings.append(newRing)
    }
}

#Preview("Pulse Rings - Active") {
    PulseRingsView(
        audioLevel: 0.6,
        isActive: true
    )
    .frame(width: 200, height: 200)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}

#Preview("Pulse Rings - Idle") {
    PulseRingsView(
        audioLevel: 0,
        isActive: false
    )
    .frame(width: 200, height: 200)
    .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
