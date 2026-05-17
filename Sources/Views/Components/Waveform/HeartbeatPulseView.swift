import SwiftUI

/// Heartbeat — one dominant ring at a time. Each peak earns one substantial
/// ring that takes ~1.4s to expand and fade. More percussive and dramatic
/// than the old multi-ring pulse style.
struct HeartbeatPulseView: View {
    let audioLevel: Float
    let isActive: Bool

    @State private var rings: [Ring] = []
    @State private var lastPeakTime: Date = .distantPast
    @State private var idlePhase: CGFloat = 0
    @State private var frameTimer = FrameTimer(interval: 0.033)

    private let coral     = Color(red: 0.85, green: 0.45, blue: 0.30)
    private let coralDeep = Color(red: 0.70, green: 0.34, blue: 0.23)
    private let cream     = Color(red: 0.85, green: 0.83, blue: 0.80)

    private let maxRings = 2
    private let ringLifetime: TimeInterval = 1.4
    private let peakThreshold: Float = 0.30
    private let peakCooldown: TimeInterval = 0.5  // longer cooldown — one ring per beat

    struct Ring: Identifiable {
        let id = UUID()
        var radius: CGFloat
        var opacity: CGFloat
        var width: CGFloat
        let createdAt: Date
    }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let coreR = size * 0.08 + CGFloat(audioLevel) * size * 0.05

            ZStack {
                // Substantial rings
                ForEach(rings) { ring in
                    // Outer halo
                    Circle()
                        .stroke(coral.opacity(ring.opacity * 0.5), lineWidth: ring.width + 8)
                        .frame(width: ring.radius * 2, height: ring.radius * 2)
                        .blur(radius: 6)
                    // Core ring
                    Circle()
                        .stroke(coral.opacity(ring.opacity), lineWidth: ring.width)
                        .frame(width: ring.radius * 2, height: ring.radius * 2)
                }

                // Soft outer glow on the core
                Circle()
                    .fill(coral.opacity(0.25 + Double(audioLevel) * 0.2))
                    .frame(width: (coreR + 8) * 2, height: (coreR + 8) * 2)
                    .blur(radius: 14)

                // Core orb
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [cream.opacity(1.0), coral.opacity(0.7), coralDeep.opacity(0.1)],
                            center: .center, startRadius: 0, endRadius: coreR
                        )
                    )
                    .frame(width: coreR * 2, height: coreR * 2)

                // Idle gentle breath when no audio
                if !isActive {
                    Circle()
                        .stroke(coral.opacity(0.15), lineWidth: 1)
                        .frame(
                            width: size * 0.32 + sin(idlePhase) * 8,
                            height: size * 0.32 + sin(idlePhase) * 8
                        )
                }
            }
            .position(center)
        }
        .onAppear { frameTimer.start() }
        .onDisappear { frameTimer.stop() }
        .onReceive(frameTimer.publisher) { _ in
            updateRings()
        }
    }

    private func updateRings() {
        idlePhase += 0.04
        let now = Date()

        // Spawn a ring on threshold crossing (with cooldown)
        if isActive && audioLevel > peakThreshold {
            if now.timeIntervalSince(lastPeakTime) > peakCooldown && rings.count < maxRings {
                spawnRing()
                lastPeakTime = now
            }
        }

        // Advance existing rings
        let size: CGFloat = 220 // physics reference size
        rings = rings.compactMap { ring in
            let age = now.timeIntervalSince(ring.createdAt)
            if age > ringLifetime { return nil }
            var updatedRing = ring
            let progress = age / ringLifetime
            // Radius grows; width tapers
            updatedRing.radius = size * 0.1 + CGFloat(progress) * size * 0.42
            updatedRing.opacity = CGFloat(pow(1 - progress, 1.5)) * 0.85
            updatedRing.width = 6 - CGFloat(progress) * 4
            return updatedRing
        }
    }

    private func spawnRing() {
        let newRing = Ring(
            radius: 20,
            opacity: 0.85,
            width: 6,
            createdAt: Date()
        )
        rings.append(newRing)
    }
}

#Preview("Heartbeat") {
    HeartbeatPulseView(audioLevel: 0.5, isActive: true)
        .frame(width: 220, height: 220)
        .background(Color(red: 0.04, green: 0.04, blue: 0.04))
}
