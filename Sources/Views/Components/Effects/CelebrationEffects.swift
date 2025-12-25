import SwiftUI

// MARK: - Main Celebration Coordinator

/// Orchestrates success celebration effects based on visual intensity style.
struct SuccessCelebration: View {
    let intensity: VisualIntensity
    let isActive: Bool
    let successColor: Color

    @State private var triggered = false

    var body: some View {
        ZStack {
            // Flash overlay (burst only)
            if intensity.showFlash && triggered {
                FlashOverlay(opacity: intensity.flashOpacity)
            }

            // Glow pulse (all styles)
            if triggered {
                GlowPulseView(
                    color: successColor,
                    intensity: intensity.glowIntensity,
                    duration: intensity.glowDuration,
                    ringCount: intensity.glowRingCount
                )
            }

            // Expanding rings (glow and balanced)
            if intensity.ringCount > 0 && triggered {
                ExpandingRingsView(
                    ringCount: intensity.ringCount,
                    color: successColor,
                    glowIntensity: intensity.glowIntensity
                )
            }

            // Confetti particles (balanced and burst)
            if intensity.confettiCount > 0 && triggered {
                ConfettiView(
                    particleCount: intensity.confettiCount,
                    sizeRange: intensity.confettiSizeRange,
                    speedRange: intensity.confettiBurstSpeed
                )
            }
        }
        .onAppear {
            if isActive && !triggered {
                triggered = true
            }
        }
        .onChange(of: isActive) { _, active in
            if active && !triggered {
                triggered = true
            }
        }
    }
}

// MARK: - Flash Overlay

/// Brief white flash for burst style success.
struct FlashOverlay: View {
    let opacity: Double
    @State private var currentOpacity: Double = 0

    var body: some View {
        Color.white
            .opacity(currentOpacity)
            .allowsHitTesting(false)
            .onAppear {
                currentOpacity = opacity
                withAnimation(.easeOut(duration: 0.2)) {
                    currentOpacity = 0
                }
            }
    }
}

// MARK: - Glow Pulse

/// Expanding glow effect from center with multiple rings for glow style.
struct GlowPulseView: View {
    let color: Color
    let intensity: Double
    let duration: Double
    let ringCount: Int

    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // Multiple glow rings for glow style
            ForEach(0..<max(1, ringCount), id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                color.opacity(0.8 * intensity),
                                color.opacity(0.5 * intensity),
                                color.opacity(0.2 * intensity),
                                color.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .scaleEffect(scale * (1.0 + CGFloat(index) * 0.4))
                    .opacity(opacity * (1.0 - Double(index) * 0.2))
                    .blur(radius: CGFloat(index) * 3)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: duration)) {
                scale = 3.0
                opacity = 1.0
            }
            withAnimation(.easeOut(duration: duration * 1.5).delay(duration * 0.8)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Expanding Rings

/// Concentric expanding rings animation.
struct ExpandingRingsView: View {
    let ringCount: Int
    let color: Color
    let glowIntensity: Double

    @State private var startTime: Date = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = max(size.width, size.height)

                for i in 0..<ringCount {
                    let delay = Double(i) * 0.12
                    let ringDuration = 1.0
                    let progress = min(1.0, max(0, (elapsed - delay) / ringDuration))

                    if progress > 0 && progress < 1.0 {
                        let radius = maxRadius * CGFloat(progress)
                        let fadeOut = 1.0 - progress
                        let opacity = fadeOut * glowIntensity

                        // Outer glow
                        let glowRing = Path { path in
                            path.addEllipse(in: CGRect(
                                x: center.x - radius - 6,
                                y: center.y - radius - 6,
                                width: (radius + 6) * 2,
                                height: (radius + 6) * 2
                            ))
                        }
                        context.stroke(
                            glowRing,
                            with: .color(color.opacity(opacity * 0.4)),
                            lineWidth: 10
                        )

                        // Core ring
                        let ring = Path { path in
                            path.addEllipse(in: CGRect(
                                x: center.x - radius,
                                y: center.y - radius,
                                width: radius * 2,
                                height: radius * 2
                            ))
                        }
                        context.stroke(
                            ring,
                            with: .color(color.opacity(opacity)),
                            lineWidth: 3 + CGFloat(fadeOut) * 3
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            startTime = Date()
        }
    }
}

// MARK: - Confetti System

/// Particle-based confetti celebration with customizable size and speed.
struct ConfettiView: View {
    let particleCount: Int
    let sizeRange: ClosedRange<CGFloat>
    let speedRange: ClosedRange<Double>

    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Date = Date()

    private let colors: [Color] = [
        Color(red: 0.0, green: 0.9, blue: 0.95),   // Cyan
        Color(red: 0.95, green: 0.2, blue: 0.8),   // Magenta
        Color(red: 1.0, green: 0.85, blue: 0.0),   // Yellow
        Color(red: 0.4, green: 0.9, blue: 0.5),    // Green
        Color(red: 0.45, green: 0.75, blue: 0.55), // Success green
        Color(red: 1.0, green: 0.6, blue: 0.4),    // Coral
        Color(red: 0.6, green: 0.4, blue: 1.0),    // Purple
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(startTime)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                for particle in particles {
                    let age = elapsed - particle.delay
                    guard age > 0, age < particle.lifetime else { continue }

                    let progress = age / particle.lifetime

                    // Physics: initial burst velocity + gravity
                    let gravity: Double = 200
                    let x = center.x + particle.velocity.x * CGFloat(age) * 55
                    let y = center.y + particle.velocity.y * CGFloat(age) * 55 + 0.5 * CGFloat(gravity) * CGFloat(age * age)

                    // Fade out and shrink
                    let opacity = 1.0 - progress * 0.6
                    let scale = particle.size * (1.0 - progress * 0.3)

                    // Rotation
                    let rotation = Angle.degrees(particle.rotation + particle.rotationSpeed * age * 60)

                    guard x >= -40, x <= size.width + 40,
                          y >= -40, y <= size.height + 40 else { continue }

                    context.opacity = opacity
                    context.translateBy(x: x, y: y)
                    context.rotate(by: rotation)

                    // Draw confetti piece
                    if particle.isCircle {
                        let circle = Path(ellipseIn: CGRect(
                            x: -scale / 2,
                            y: -scale / 2,
                            width: scale,
                            height: scale
                        ))
                        context.fill(circle, with: .color(particle.color))
                    } else {
                        let rect = Path(roundedRect: CGRect(
                            x: -scale / 2,
                            y: -scale / 4,
                            width: scale,
                            height: scale / 2
                        ), cornerRadius: 2)
                        context.fill(rect, with: .color(particle.color))
                    }

                    context.rotate(by: -rotation)
                    context.translateBy(x: -x, y: -y)
                    context.opacity = 1.0
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            spawnParticles()
        }
    }

    private func spawnParticles() {
        startTime = Date()
        particles = (0..<particleCount).map { i in
            // Wider angle for more spread (-160° to -20°)
            let angle = Double.random(in: (-Double.pi * 0.9)...(-Double.pi * 0.1))
            let speed = Double.random(in: speedRange)
            return ConfettiParticle(
                velocity: CGPoint(
                    x: cos(angle) * speed,
                    y: sin(angle) * speed
                ),
                color: colors.randomElement() ?? .white,
                size: CGFloat.random(in: sizeRange),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -8...8),
                lifetime: Double.random(in: 1.2...1.8),
                delay: Double(i) * 0.012,
                isCircle: Bool.random()
            )
        }
    }
}

struct ConfettiParticle: Identifiable {
    let id = UUID()
    let velocity: CGPoint
    let color: Color
    let size: CGFloat
    let rotation: Double
    let rotationSpeed: Double
    let lifetime: Double
    let delay: Double
    let isCircle: Bool
}

// MARK: - Previews

#Preview("Celebration - Glow") {
    ZStack {
        Color.black
        SuccessCelebration(
            intensity: .glow,
            isActive: true,
            successColor: Color(red: 0.45, green: 0.75, blue: 0.55)
        )
    }
    .frame(width: 350, height: 160)
}

#Preview("Celebration - Balanced") {
    ZStack {
        Color.black
        SuccessCelebration(
            intensity: .balanced,
            isActive: true,
            successColor: Color(red: 0.45, green: 0.75, blue: 0.55)
        )
    }
    .frame(width: 350, height: 160)
}

#Preview("Celebration - Burst") {
    ZStack {
        Color.black
        SuccessCelebration(
            intensity: .burst,
            isActive: true,
            successColor: Color(red: 0.45, green: 0.75, blue: 0.55)
        )
    }
    .frame(width: 350, height: 160)
}
