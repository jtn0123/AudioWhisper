import SwiftUI

// MARK: - Main Celebration Coordinator

/// Orchestrates success celebration effects based on visual intensity.
struct SuccessCelebration: View {
    let intensity: VisualIntensity
    let isActive: Bool
    let successColor: Color

    @State private var showFlash = false
    @State private var showGlow = false
    @State private var showConfetti = false
    @State private var showRings = false
    @State private var checkmarkScale: CGFloat = 0.8
    @State private var checkmarkOpacity: Double = 0

    var body: some View {
        ZStack {
            // Flash overlay (bold only)
            if intensity.showFlash && showFlash {
                FlashOverlay(isActive: $showFlash)
            }

            // Expanding rings
            if intensity.ringCount > 0 && showRings {
                ExpandingRingsView(
                    ringCount: intensity.ringCount,
                    color: successColor,
                    isActive: showRings
                )
            }

            // Glow pulse
            if intensity.glowIntensity > 0 && showGlow {
                GlowPulseView(
                    color: successColor,
                    intensity: intensity.glowIntensity,
                    isActive: showGlow
                )
            }

            // Confetti particles
            if intensity.confettiCount > 0 && showConfetti {
                ConfettiView(
                    particleCount: intensity.confettiCount,
                    isActive: showConfetti
                )
            }
        }
        .onChange(of: isActive) { _, active in
            if active {
                triggerCelebration()
            } else {
                resetCelebration()
            }
        }
        .onAppear {
            if isActive {
                triggerCelebration()
            }
        }
    }

    private func triggerCelebration() {
        // Stagger effects for visual impact
        withAnimation(.easeOut(duration: 0.1)) {
            showFlash = true
        }

        withAnimation(intensity.spring.delay(0.05)) {
            showGlow = true
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }

        withAnimation(.easeOut(duration: 0.2).delay(0.1)) {
            showRings = true
        }

        withAnimation(.easeOut(duration: 0.15).delay(0.15)) {
            showConfetti = true
        }
    }

    private func resetCelebration() {
        showFlash = false
        showGlow = false
        showConfetti = false
        showRings = false
        checkmarkScale = 0.8
        checkmarkOpacity = 0
    }
}

// MARK: - Flash Overlay

/// Brief white flash for bold intensity success.
struct FlashOverlay: View {
    @Binding var isActive: Bool
    @State private var opacity: Double = 0.6

    var body: some View {
        Color.white
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.15)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isActive = false
                }
            }
    }
}

// MARK: - Glow Pulse

/// Expanding glow effect from center.
struct GlowPulseView: View {
    let color: Color
    let intensity: Double
    let isActive: Bool

    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.6 * intensity),
                        color.opacity(0.3 * intensity),
                        color.opacity(0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 100
                )
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: isActive) { _, active in
                if active {
                    animate()
                } else {
                    reset()
                }
            }
            .onAppear {
                if isActive {
                    animate()
                }
            }
    }

    private func animate() {
        withAnimation(.easeOut(duration: 0.4)) {
            scale = 2.0
            opacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.4)) {
            opacity = 0
        }
    }

    private func reset() {
        scale = 0.5
        opacity = 0
    }
}

// MARK: - Expanding Rings

/// Concentric expanding rings animation.
struct ExpandingRingsView: View {
    let ringCount: Int
    let color: Color
    let isActive: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = max(size.width, size.height) * 0.8

                for i in 0..<ringCount {
                    let delay = Double(i) * 0.1
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let progress = min(1.0, max(0, (elapsed.truncatingRemainder(dividingBy: 2.0) - delay) / 1.0))

                    if progress > 0 {
                        let radius = maxRadius * progress
                        let opacity = 1.0 - progress

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
                            with: .color(color.opacity(opacity * 0.8)),
                            lineWidth: 2 + (1 - progress) * 2
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Ring Model (for non-Canvas approach)

struct Ring: Identifiable {
    let id = UUID()
    var scale: CGFloat = 0.2
    var opacity: Double = 1.0
}

// MARK: - Confetti System

/// Particle-based confetti celebration.
struct ConfettiView: View {
    let particleCount: Int
    let isActive: Bool

    @State private var particles: [ConfettiParticle] = []
    @State private var startTime: Date?

    private let colors: [Color] = [
        Color(red: 0.0, green: 0.9, blue: 0.95),   // Cyan
        Color(red: 0.95, green: 0.2, blue: 0.8),   // Magenta
        Color(red: 1.0, green: 0.85, blue: 0.0),   // Yellow
        Color(red: 0.4, green: 0.9, blue: 0.5),    // Green
        Color(red: 0.45, green: 0.75, blue: 0.55), // Success green
        Color(red: 1.0, green: 0.6, blue: 0.4),    // Coral
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let elapsed = startTime.map { timeline.date.timeIntervalSince($0) } ?? 0
                let center = CGPoint(x: size.width / 2, y: size.height / 2)

                for particle in particles {
                    let age = elapsed - particle.delay
                    guard age > 0, age < particle.lifetime else { continue }

                    let progress = age / particle.lifetime

                    // Physics: initial burst velocity + gravity
                    let x = center.x + particle.velocity.x * CGFloat(age) * 60
                    let y = center.y + particle.velocity.y * CGFloat(age) * 60 + 0.5 * 200 * CGFloat(age * age)

                    // Fade out and shrink
                    let opacity = 1.0 - progress
                    let scale = particle.size * (1.0 - progress * 0.5)

                    // Rotation
                    let rotation = Angle.degrees(particle.rotation + particle.rotationSpeed * age * 60)

                    guard x >= -20, x <= size.width + 20,
                          y >= -20, y <= size.height + 20 else { continue }

                    context.opacity = opacity
                    context.translateBy(x: x, y: y)
                    context.rotate(by: rotation)

                    // Draw confetti piece (small rectangle or circle)
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
                        ), cornerRadius: 1)
                        context.fill(rect, with: .color(particle.color))
                    }

                    context.rotate(by: -rotation)
                    context.translateBy(x: -x, y: -y)
                    context.opacity = 1.0
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active {
                spawnParticles()
            }
        }
        .onAppear {
            if isActive {
                spawnParticles()
            }
        }
    }

    private func spawnParticles() {
        startTime = Date()
        particles = (0..<particleCount).map { i in
            let angle = Double.random(in: -Double.pi...0) // Upward burst
            let speed = Double.random(in: 2...5)
            return ConfettiParticle(
                velocity: CGPoint(
                    x: cos(angle) * speed,
                    y: sin(angle) * speed
                ),
                color: colors.randomElement() ?? .white,
                size: CGFloat.random(in: 6...12),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -5...5),
                lifetime: Double.random(in: 1.2...1.8),
                delay: Double(i) * 0.02,
                isCircle: Bool.random()
            )
        }

        // Clear after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            particles = []
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

#Preview("Celebration - Subtle") {
    ZStack {
        Color.black
        SuccessCelebration(
            intensity: .subtle,
            isActive: true,
            successColor: Color(red: 0.45, green: 0.75, blue: 0.55)
        )
    }
    .frame(width: 350, height: 160)
}

#Preview("Celebration - Expressive") {
    ZStack {
        Color.black
        SuccessCelebration(
            intensity: .expressive,
            isActive: true,
            successColor: Color(red: 0.45, green: 0.75, blue: 0.55)
        )
    }
    .frame(width: 350, height: 160)
}

#Preview("Celebration - Bold") {
    ZStack {
        Color.black
        SuccessCelebration(
            intensity: .bold,
            isActive: true,
            successColor: Color(red: 0.45, green: 0.75, blue: 0.55)
        )
    }
    .frame(width: 350, height: 160)
}
