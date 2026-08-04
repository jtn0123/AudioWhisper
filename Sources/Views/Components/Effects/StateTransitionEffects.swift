import SwiftUI

// MARK: - Entry Animation Modifier

/// Animates content appearing with scale and opacity based on intensity.
struct EntryAnimationModifier: ViewModifier {
    let intensity: VisualIntensity
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible ? 1.0 : intensity.entryScale)
            .opacity(isVisible ? 1.0 : 0)
            .rotationEffect(.degrees(isVisible ? 0 : intensity.entryRotation))
            .onAppear {
                withAnimation(intensity.spring) {
                    isVisible = true
                }
            }
    }
}

extension View {
}

// MARK: - Recording Start Pulse

/// A ripple effect that emanates from center when recording starts.
struct RecordingStartPulse: View {
    let intensity: VisualIntensity
    let isActive: Bool
    let color: Color

    @State private var pulseScale: CGFloat = 0.3
    @State private var pulseOpacity: Double = 0

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 3 * intensity.glowIntensity)
            .scaleEffect(pulseScale)
            .opacity(pulseOpacity)
            .blur(radius: 2 * intensity.glowIntensity)
            .allowsHitTesting(false)
            .onChange(of: isActive) { _, active in
                if active {
                    triggerPulse()
                }
            }
    }

    private func triggerPulse() {
        pulseScale = 0.3
        pulseOpacity = intensity.glowIntensity

        withAnimation(.easeOut(duration: intensity.transitionDuration * 1.5)) {
            pulseScale = 1.5
            pulseOpacity = 0
        }
    }
}

// MARK: - Processing Wave

/// Subtle wave animation during processing state.
struct ProcessingWave: View {
    let intensity: VisualIntensity
    let isActive: Bool

    var body: some View {
        if isActive {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let wavePhase = elapsed * 2

                    let path = Path { path in
                        path.move(to: CGPoint(x: 0, y: size.height / 2))

                        for posX in stride(from: 0, through: size.width, by: 2) {
                            let normalizedX = Double(posX / size.width)
                            let wave1 = sin(normalizedX * Double.pi * 4 + wavePhase) * 3
                            let wave2 = sin(normalizedX * Double.pi * 2 + wavePhase * 0.7) * 2
                            let posY = size.height / 2 + CGFloat(wave1 + wave2) * CGFloat(intensity.glowIntensity)
                            path.addLine(to: CGPoint(x: posX, y: posY))
                        }
                    }

                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.15 * intensity.glowIntensity)),
                        lineWidth: 1
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Error Shake Modifier

/// Shakes the view when triggered (for error states).
struct ShakeModifier: ViewModifier {
    let isShaking: Bool
    let intensity: VisualIntensity

    @State private var shakeOffset: CGFloat = 0

    /// C2: a shake is the single most motion-sensitive effect here, and the
    /// error is already conveyed by colour and the status label.
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: isShaking) { _, shake in
                if shake && !reduceMotion {
                    triggerShake()
                }
            }
    }

    private func triggerShake() {
        // All styles use consistent expressive-level shake
        let shakeAmount: CGFloat = 5
        let duration = 0.08

        // Quick shake sequence
        withAnimation(.easeInOut(duration: duration)) {
            shakeOffset = shakeAmount
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: duration)) {
                shakeOffset = -shakeAmount
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 2) {
            withAnimation(.easeInOut(duration: duration)) {
                shakeOffset = shakeAmount * 0.5
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 3) {
            withAnimation(.easeInOut(duration: duration)) {
                shakeOffset = 0
            }
        }
    }
}

extension View {
    /// Applies shake animation when triggered.
    /// `reduceMotion` is passed by the caller (which reads the environment) —
    /// see the note on `ShakeModifier`.
    func shake(when isShaking: Bool, intensity: VisualIntensity, reduceMotion: Bool = false) -> some View {
        modifier(ShakeModifier(isShaking: isShaking, intensity: intensity, reduceMotion: reduceMotion))
    }
}

// MARK: - Error Flash

/// Red flash overlay for error states.
struct ErrorFlash: View {
    let intensity: VisualIntensity
    let isActive: Bool

    @State private var opacity: Double = 0

    var body: some View {
        Color.red
            .opacity(opacity)
            .allowsHitTesting(false)
            .onChange(of: isActive) { _, active in
                if active {
                    flash()
                }
            }
    }

    private func flash() {
        // All styles use consistent expressive-level flash
        let flashOpacity = 0.25

        withAnimation(.easeIn(duration: 0.1)) {
            opacity = flashOpacity
        }

        withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
            opacity = 0
        }
    }
}

// MARK: - Status Transition Overlay

/// Coordinates all transition effects based on status changes.
struct StatusTransitionOverlay: View {
    let fromStatus: AppStatus?
    let toStatus: AppStatus
    let intensity: VisualIntensity

    private let accentColor = Color(red: 0.85, green: 0.45, blue: 0.40)

    /// C2: state changes are also communicated by the status dot and label, so
    /// the transition flourish is safe to drop under Reduce Motion.
    var reduceMotion: Bool = false

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            animatedBody
        }
    }

    private var animatedBody: some View {
        ZStack {
            // Recording start pulse
            if isTransitionToRecording {
                RecordingStartPulse(
                    intensity: intensity,
                    isActive: true,
                    color: accentColor
                )
            }

            // Processing wave
            if isProcessing {
                ProcessingWave(
                    intensity: intensity,
                    isActive: true
                )
            }

            // Error flash
            if isError {
                ErrorFlash(
                    intensity: intensity,
                    isActive: true
                )
            }
        }
    }

    private var isTransitionToRecording: Bool {
        if case .recording = toStatus {
            if case .recording = fromStatus {
                return false // Already recording
            }
            return true
        }
        return false
    }

    private var isProcessing: Bool {
        if case .processing = toStatus {
            return true
        }
        return false
    }

    private var isError: Bool {
        if case .error = toStatus {
            return true
        }
        return false
    }
}

// MARK: - Enhanced Status Dot

/// Status indicator dot with intensity-based glow effects.
struct EnhancedStatusDot: View {
    let color: Color
    let intensity: VisualIntensity
    let isPulsing: Bool

    @State private var pulseOpacity: Double = 1.0

    var body: some View {
        ZStack {
            // Glow layer (all styles use glow now)
            if intensity.dotGlow {
                Circle()
                    .fill(color)
                    .frame(width: 6 + intensity.dotGlowRadius, height: 6 + intensity.dotGlowRadius)
                    .blur(radius: intensity.dotGlowRadius)
                    .opacity(pulseOpacity * 0.6)
            }

            // Core dot
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .opacity(pulseOpacity)
        }
        .onChange(of: isPulsing) { _, pulsing in
            if pulsing {
                startPulsing()
            } else {
                stopPulsing()
            }
        }
        .onAppear {
            if isPulsing {
                startPulsing()
            }
        }
    }

    private func startPulsing() {
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseOpacity = 0.4
        }
    }

    private func stopPulsing() {
        withAnimation(.easeOut(duration: 0.2)) {
            pulseOpacity = 1.0
        }
    }
}

// MARK: - Previews

#Preview("Recording Start Pulse") {
    ZStack {
        Color.black
        RecordingStartPulse(
            intensity: .glow,
            isActive: true,
            color: Color(red: 0.85, green: 0.45, blue: 0.40)
        )
    }
    .frame(width: 350, height: 160)
}

#Preview("Processing Wave") {
    ZStack {
        Color.black
        ProcessingWave(intensity: .balanced, isActive: true)
    }
    .frame(width: 350, height: 160)
}

#Preview("Enhanced Dot - Pulsing") {
    ZStack {
        Color.black
        EnhancedStatusDot(
            color: Color(red: 0.85, green: 0.45, blue: 0.40),
            intensity: .burst,
            isPulsing: true
        )
    }
    .frame(width: 100, height: 100)
}
