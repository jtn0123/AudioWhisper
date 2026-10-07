import SwiftUI

/// Container view that switches between waveform visualization styles.
///
/// Visual direction "B · Frameless + glow" from the design canvas:
/// - No rounded-rectangle stroke; the window sits on a soft outer shadow plus
///   a state-aware colored glow (coral while listening, sage on success,
///   faint coral on error).
/// - A radial vignette recesses the waveform.
/// - The status row floats — left shows the dot + label, right shows
///   contextual info (live timer while recording, ⌘⇧Space keycap when ready,
///   duration recap on success).
/// - `.processing` swaps the breathing bars for a scanning shimmer so there
///   is no fake waveform when there is no audio.
struct WaveformContainer: View {
    let status: AppStatus
    let audioLevel: Float
    let waveformSamples: [Float]
    let frequencyBands: [Float]
    /// When false, animations inside the `.processing` indicator are
    /// suppressed so snapshot tests render a deterministic frame.
    /// Production callers should leave this at the default (`true`).
    let processingAnimated: Bool
    let completedAudioDuration: TimeInterval?
    /// Hosts that draw their own status and timer (the rebuild HUD) hide the
    /// built-in floating row so the state is not shown twice.
    let showsStatusRow: Bool
    /// Hosts can supply opaque chrome without changing the selected visualizer
    /// or the shared component's default appearance.
    let showsGlassBackground: Bool
    let backgroundColor: Color
    let waveformColor: Color
    let onTap: () -> Void

    init(
        status: AppStatus,
        audioLevel: Float,
        waveformSamples: [Float],
        frequencyBands: [Float],
        processingAnimated: Bool = true,
        completedAudioDuration: TimeInterval? = nil,
        showsStatusRow: Bool = true,
        showsGlassBackground: Bool = true,
        backgroundColor: Color = WaveformPalette.background,
        waveformColor: Color = WaveformPalette.bar,
        onTap: @escaping () -> Void
    ) {
        self.status = status
        self.audioLevel = audioLevel
        self.waveformSamples = waveformSamples
        self.frequencyBands = frequencyBands
        self.processingAnimated = processingAnimated
        self.completedAudioDuration = completedAudioDuration
        self.showsStatusRow = showsStatusRow
        self.showsGlassBackground = showsGlassBackground
        self.backgroundColor = backgroundColor
        self.waveformColor = waveformColor
        self.onTap = onTap
    }

    @AppDefault(\.waveformStyle) private var waveformStyle
    @AppDefault(\.visualIntensity) private var visualIntensity

    /// C2: single place the Reduce Motion setting is read. It is passed down to
    /// the decorative effects rather than each of them reaching for the
    /// environment, which also makes them testable —
    /// `accessibilityReduceMotion` is a read-only key that cannot be injected.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var previousStatus: AppStatus?
    @State private var showError = false
    @State private var recordingStartedAt: Date?

    // Colors (sourced from WaveformPalette so the theme owns the literals)
    private var creamColor: Color { waveformColor }
    private let creamDim = WaveformPalette.creamDim
    private let mutedColor = WaveformPalette.muted
    private let successColor = WaveformPalette.success
    private let coralColor = WaveformPalette.accent
    private let amberColor = WaveformPalette.amber

    private var style: WaveformStyle { waveformStyle }
    private var intensity: VisualIntensity { visualIntensity }

    private let cornerRadius: CGFloat = 22

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Solid base
                backgroundColor

                // Glass background (expressive / bold intensities only)
                if showsGlassBackground && intensity.showGlass {
                    GlassBackground(intensity: intensity, cornerRadius: cornerRadius)
                        .opacity(0.85)
                }

                // Inner vignette — pulls focus to the waveform
                vignette

                // Main visualization (bars / shimmer / glyph swap by state)
                stateVisual

                // Particle overlay for neon style while recording
                if style == .neon && isRecording {
                    ParticleOverlay(audioLevel: audioLevel, isActive: true, reduceMotion: reduceMotion)
                        .opacity(intensity.particleMultiplier)
                }

                // State transition flourish. While processing, the transition
                // animation is non-deterministic; tests suppress it via
                // processingAnimated.
                if processingAnimated || !isProcessing {
                    StatusTransitionOverlay(
                        fromStatus: previousStatus,
                        toStatus: status,
                        intensity: intensity,
                        reduceMotion: reduceMotion
                    )
                }

                // Success celebration
                if isSuccess {
                    SuccessCelebration(
                        intensity: intensity,
                        isActive: true,
                        successColor: successColor,
                        reduceMotion: reduceMotion
                    )
                    .opacity(0.7)
                }

                // Status row — floats, no chrome
                if showsStatusRow { statusRow }
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Outer soft shadow — always on
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 16)
        // State-aware colored glow — gives each state its own ambient color
        .shadow(color: glowColor, radius: glowRadius, x: 0, y: 0)
        .shake(when: showError, intensity: intensity, reduceMotion: reduceMotion)
        .onChange(of: status) { oldStatus, newStatus in
            previousStatus = oldStatus
            if case .recording = newStatus {
                recordingStartedAt = Date()
            } else if case .recording = oldStatus {
                // Hold the timestamp briefly so the success recap can show duration.
                if !isSuccess { recordingStartedAt = nil }
            }
            if case .error = newStatus {
                showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showError = false
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityAction)
        .accessibilityValue(status.message)
    }

    // MARK: - Chrome layers

    @ViewBuilder
    private var vignette: some View {
        RadialGradient(
            colors: [.clear, Color.black.opacity(0.55)],
            center: .center,
            startRadius: 60,
            endRadius: 220
        )
        .blendMode(.multiply)
        .allowsHitTesting(false)
    }

    // MARK: - State visual

    @ViewBuilder
    private var stateVisual: some View {
        switch status {
        case .processing:
            ProcessingShimmerView(color: creamColor.opacity(0.85), animated: processingAnimated && !reduceMotion)
                .padding(.horizontal, 24)

        case .success:
            ZStack {
                waveformView
                    .opacity(0.35)
                successBadge
            }

        case .error:
            ZStack {
                waveformView
                    .opacity(0.25)
                errorGlyph
            }

        default:
            waveformView
        }
    }

    // MARK: - Waveform View

    @ViewBuilder
    private var waveformView: some View {
        switch style {
        case .classic:
            ClassicWaveformView(
                audioLevel: audioLevel,
                isActive: isRecording,
                barColor: currentBarColor
            )
        case .neon:
            NeonWaveformView(
                waveformSamples: waveformSamples,
                audioLevel: audioLevel,
                isActive: isRecording
            )
        case .spectrum:
            SpectrumWaveformView(
                frequencyBands: frequencyBands,
                isActive: isRecording
            )
        case .stream:
            StreamWaveformView(
                audioLevel: audioLevel,
                isActive: isRecording
            )
        case .constellation:
            ConstellationWaveformView(
                audioLevel: audioLevel,
                isActive: isRecording
            )
        case .halo:
            HaloWaveformView(
                frequencyBands: frequencyBands,
                audioLevel: audioLevel,
                isActive: isRecording
            )
        case .dial:
            DialWaveformView(
                frequencyBands: frequencyBands,
                audioLevel: audioLevel,
                isActive: isRecording
            )
        case .heartbeat:
            HeartbeatPulseView(
                audioLevel: audioLevel,
                isActive: isRecording
            )
        }
    }

}

extension WaveformContainer {
    // MARK: - State badges

    private var successBadge: some View {
        Circle()
            .fill(successColor.opacity(0.12))
            .overlay(
                Circle().stroke(successColor.opacity(0.4), lineWidth: 1)
            )
            .overlay(
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(successColor)
            )
            .frame(width: 64, height: 64)
            .shadow(color: successColor.opacity(0.35), radius: 18)
    }

    private var errorGlyph: some View {
        Circle()
            .stroke(coralColor.opacity(0.45), lineWidth: 1)
            .overlay(
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(coralColor)
            )
            .frame(width: 64, height: 64)
    }

    // MARK: - Status row

    @ViewBuilder
    private var statusRow: some View {
        VStack {
            Spacer()
            HStack(alignment: .center, spacing: 0) {
                // Left: dot + label
                HStack(spacing: 8) {
                    if shouldShowDot {
                        EnhancedStatusDot(
                            color: dotColor,
                            intensity: intensity,
                            isPulsing: shouldPulseStatusDot
                        )
                    }
                    Text(statusText)
                        .font(.system(size: 10, weight: .semibold, design: .default))
                        .tracking(1.6)
                        .foregroundStyle(statusTextColor)
                }

                Spacer()

                // Right: contextual info
                Group {
                    switch status {
                    case .recording:
                        TimerLabel(start: recordingStartedAt)
                    case .ready:
                        HotkeyHint()
                    case .success:
                        SuccessRecapLabel(duration: completedAudioDuration, wordCount: nil)
                    default:
                        EmptyView()
                    }
                }
                .foregroundStyle(Color.white.opacity(0.32))
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 1)
        }
    }

}

// MARK: - State Helpers

extension WaveformContainer {
    private var isRecording: Bool {
        if case .recording = status { return true }
        return false
    }

    private var isProcessing: Bool {
        if case .processing = status { return true }
        return false
    }

    private var isSuccess: Bool {
        if case .success = status { return true }
        return false
    }

    private var shouldShowDot: Bool {
        switch status {
        case .recording, .processing, .success, .error:
            return true
        default:
            return false
        }
    }

    /// Whether the status dot should pulse. Tests can disable processing
    /// animations via `processingAnimated` to keep snapshots deterministic.
    private var shouldPulseStatusDot: Bool {
        guard !reduceMotion else { return false }
        if isRecording { return true }
        if isProcessing { return processingAnimated }
        return false
    }

    private var dotColor: Color {
        switch status {
        case .recording:          return coralColor
        case .processing:         return amberColor
        case .success:            return successColor
        case .error:              return coralColor
        case .ready:              return creamDim
        case .permissionRequired, .setupRequired: return mutedColor
        }
    }

    private var currentBarColor: Color {
        switch status {
        case .recording:  return creamColor
        case .processing: return creamColor.opacity(0.6)
        case .success:    return successColor
        case .error:      return coralColor
        default:          return creamColor.opacity(0.35) // ready: barely-there breathing
        }
    }

    private var statusTextColor: Color {
        switch status {
        case .recording:  return .white.opacity(0.7)
        case .processing: return .white.opacity(0.6)
        case .success:    return successColor
        case .error:      return coralColor
        default:          return .white.opacity(0.45)
        }
    }

    private var statusText: String {
        switch status {
        case .recording:           return "LISTENING"
        case .processing(let message): return message.uppercased()
        case .success:             return "COPIED"
        case .ready:               return "TAP TO RECORD"
        case .permissionRequired:  return "PERMISSION NEEDED"
        case .setupRequired:       return "FINISH SETUP"
        case .error(let message):  return message.uppercased()
        }
    }

    private var accessibilityAction: String {
        switch status {
        case .recording: return "Stop recording"
        case .processing: return "Transcribing recording"
        case .success: return "Transcript copied"
        case .permissionRequired, .setupRequired: return "Open recording setup"
        case .error: return "Try recording again"
        case .ready: return "Start recording"
        }
    }

    // Glow color/strength keyed off state
    private var glowColor: Color {
        switch status {
        case .recording: return coralColor.opacity(0.35)
        case .success:   return successColor.opacity(0.30)
        case .error:     return coralColor.opacity(0.22)
        default:         return .clear
        }
    }

    private var glowRadius: CGFloat {
        switch status {
        case .recording: return 48
        case .success:   return 40
        case .error:     return 32
        default:         return 0
        }
    }
}

// MARK: - Previews

#Preview("Container - Classic Recording") {
    WaveformContainer(
        status: .recording,
        audioLevel: 0.6,
        waveformSamples: [],
        frequencyBands: Array(repeating: 0.5, count: 8),
        onTap: {}
    )
    .frame(width: 280, height: 160)
    .padding(40)
    .background(Color.black)
}

#Preview("Container - Ready") {
    WaveformContainer(
        status: .ready,
        audioLevel: 0,
        waveformSamples: [],
        frequencyBands: Array(repeating: 0, count: 8),
        onTap: {}
    )
    .frame(width: 280, height: 160)
    .padding(40)
    .background(Color.black)
}
