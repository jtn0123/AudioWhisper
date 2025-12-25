import SwiftUI

// MARK: - Main Celebration Coordinator

/// Orchestrates success celebration effects based on visual intensity style.
struct SuccessCelebration: View {
    let intensity: VisualIntensity
    let isActive: Bool
    let successColor: Color

    @State private var showFlash = false
    @State private var showGlow = false
    @State private var showConfetti = false
    @State private var showRings = false

    var body: some View {
        ZStack {
            // Flash overlay (burst only)
            if intensity.showFlash && showFlash {
                FlashOverlay(opacity: intensity.flashOpacity, isActive: $showFlash)
            }

            // Expanding rings (glow and balanced)
            if intensity.ringCount > 0 && showRings {
                ExpandingRingsView(
                    ringCount: intensity.ringCount,
                    color: successColor,
                    glowIntensity: intensity.glowIntensity,
                    isActive: showRings
                )
            }

            // Glow pulse (all styles, but strongest for glow)
            if intensity.glowIntensity > 0 && showGlow {
                GlowPulseView(
                    color: successColor,
                    intensity: intensity.glowIntensity,
                    duration: intensity.glowDuration,
                    ringCount: intensity.glowRingCount,
                    isActive: showGlow
                )
            }

            // Confetti particles (balanced and burst)
            if intensity.confettiCount > 0 && showConfetti {
                ConfettiView(
                    particleCount: intensity.confettiCount,
                    sizeRange: intensity.confettiSizeRange,
                    speedRange: intensity.confettiBurstSpeed,
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
        // Flash first (burst only)
        if intensity.showFlash {
            withAnimation(.easeOut(duration: 0.1)) {
                showFlash = true
            }
        }

        // Glow pulse
        withAnimation(intensity.spring.delay(0.05)) {
            showGlow = true
        }

        // Rings
        if intensity.ringCount > 0 {
            withAnimation(.easeOut(duration: 0.2).delay(0.1)) {
                showRings = true
            }
        }

        // Confetti last
        if intensity.confettiCount > 0 {
            withAnimation(.easeOut(duration: 0.15).delay(0.1)) {
                showConfetti = true
            }
        }
    }

    private func resetCelebration() {
        showFlash = false
        showGlow = false
        showConfetti = false
        showRings = false
    }
}

// MARK: - Flash Overlay

/// Brief white flash for burst style success.
struct FlashOverlay: View {
    let opacity: Double
    @Binding var isActive: Bool
    @State private var currentOpacity: Double = 0

    var body: some View {
        Color.white
            .opacity(currentOpacity)
            .allowsHitTesting(false)
            .onAppear {
                currentOpacity = opacity
                withAnimation(.easeOut(duration: 0.15)) {
                    currentOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    isActive = false
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
    let isActive: Bool

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
                                color.opacity(0.7 * intensity),
                                color.opacity(0.4 * intensity),
                                color.opacity(0.1 * intensity),
                                color.opacity(0)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 120
                        )
                    )
                    .scaleEffect(scale * (1.0 + CGFloat(index) * 0.3))
                    .opacity(opacity * (1.0 - Double(index) * 0.25))
                    .blur(radius: CGFloat(index) * 2)
            }
        }
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
        withAnimation(.easeOut(duration: duration)) {
            scale = 2.5
            opacity = 1.0
        }
        withAnimation(.easeOut(duration: duration * 1.2).delay(duration)) {
            opacity = 0
        }
    }

    private func reset() {
        scale = 0.3
        opacity = 0
    }
}

// MARK: - Expanding Rings

/// Concentric expanding rings animation.
struct ExpandingRingsView: View {
    let ringCount: Int
    let color: Color
    let glowIntensity: Double
    let isActive: Bool

    @State private var startTime: Date?

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                guard let start = startTime else { return }
                let elapsed = timeline.date.timeIntervalSince(start)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxRadius = max(size.width, size.height) * 0.9

                for i in 0..<ringCount {
                    let delay = Double(i) * 0.15
                    let progress = min(1.0, max(0, (elapsed - delay) / 1.2))

                    if progress > 0 && progress < 1.0 {
                        let radius = maxRadius * CGFloat(progress)
                        let opacity = (1.0 - progress) * glowIntensity

                        // Outer glow
                        let glowRing = Path { path in
                            path.addEllipse(in: CGRect(
                                x: center.x - radius - 4,
                                y: center.y - radius - 4,
                                width: (radius + 4) * 2,
                                height: (radius + 4) * 2
                            ))
                        }
                        context.stroke(
                            glowRing,
                            with: .color(color.opacity(opacity * 0.3)),
                            lineWidth: 8
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
                            with: .color(color.opacity(opacity * 0.9)),
                            lineWidth: 2 + CGFloat(1 - progress) * 2
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in
            if active {
                startTime = Date()
            }
        }
        .onAppear {
            if isActive {
                startTime = Date()
            }
        }
    }
}

// MARK: - Confetti System

/// Particle-based confetti celebration with customizable size and speed.
struct ConfettiView: View {
    let particleCount: Int
    let sizeRange: ClosedRange<CGFloat>
    let speedRange: ClosedRange<Double>
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
        Color(red: 0.6, green: 0.4, blue: 1.0),    // Purple
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
                    let gravity: Double = 180
                    let x = center.x + particle.velocity.x * CGFloat(age) * 50
                    let y = center.y + particle.velocity.y * CGFloat(age) * 50 + 0.5 * CGFloat(gravity) * CGFloat(age * age)

                    // Fade out and shrink
                    let opacity = 1.0 - progress * 0.7
                    let scale = particle.size * (1.0 - progress * 0.4)

                    // Rotation
                    let rotation = Angle.degrees(particle.rotation + particle.rotationSpeed * age * 50)

                    guard x >= -30, x <= size.width + 30,
                          y >= -30, y <= size.height + 30 else { continue }

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
            // Wider angle for more spread (-150° to -30°)
            let angle = Double.random(in: (-Double.pi * 0.85)...(-Double.pi * 0.15))
            let speed = Double.random(in: speedRange)
            return ConfettiParticle(
                velocity: CGPoint(
                    x: cos(angle) * speed,
                    y: sin(angle) * speed
                ),
                color: colors.randomElement() ?? .white,
                size: CGFloat.random(in: sizeRange),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -6...6),
                lifetime: Double.random(in: 1.0...1.6),
                delay: Double(i) * 0.015,
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
