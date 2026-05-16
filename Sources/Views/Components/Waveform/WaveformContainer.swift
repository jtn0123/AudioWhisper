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
    let onTap: () -> Void

    init(
        status: AppStatus,
        audioLevel: Float,
        waveformSamples: [Float],
        frequencyBands: [Float],
        processingAnimated: Bool = true,
        onTap: @escaping () -> Void
    ) {
        self.status = status
        self.audioLevel = audioLevel
        self.waveformSamples = waveformSamples
        self.frequencyBands = frequencyBands
        self.processingAnimated = processingAnimated
        self.onTap = onTap
    }

    @AppDefault(\.waveformStyle) private var waveformStyle
    @AppDefault(\.visualIntensity) private var visualIntensity

    @State private var previousStatus: AppStatus?
    @State private var showError = false
    @State private var recordingStartedAt: Date?

    // Colors (sourced from WaveformPalette so the theme owns the literals)
    private let bgColor = WaveformPalette.background
    private let creamColor = WaveformPalette.bar
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
                bgColor

                // Glass background (expressive / bold intensities only)
                if intensity.showGlass {
                    GlassBackground(intensity: intensity, cornerRadius: cornerRadius)
                        .opacity(0.85)
                }

                // Inner vignette — pulls focus to the waveform
                vignette

                // Main visualization (bars / shimmer / glyph swap by state)
                stateVisual

                // Particle overlay for neon style while recording
                if style == .neon && isRecording {
                    ParticleOverlay(audioLevel: audioLevel, isActive: true)
                        .opacity(intensity.particleMultiplier)
                }

                // State transition flourish. While processing, the transition
                // animation is non-deterministic; tests suppress it via
                // processingAnimated.
                if processingAnimated || !isProcessing {
                    StatusTransitionOverlay(
                        fromStatus: previousStatus,
                        toStatus: status,
                        intensity: intensity
                    )
                }

                // Success celebration
                if isSuccess {
                    SuccessCelebration(
                        intensity: intensity,
                        isActive: true,
                        successColor: successColor
                    )
                    .opacity(0.7)
                }

                // Status row — floats, no chrome
                statusRow
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        // Outer soft shadow — always on
        .shadow(color: .black.opacity(0.55), radius: 30, x: 0, y: 16)
        // State-aware colored glow — gives each state its own ambient color
        .shadow(color: glowColor, radius: glowRadius, x: 0, y: 0)
        .shake(when: showError, intensity: intensity)
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
        .accessibilityLabel("Recording waveform")
        .accessibilityValue(isRecording ? "Active" : "Idle")
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
            ProcessingShimmerView(color: creamColor.opacity(0.85), animated: processingAnimated)
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
                        SuccessRecapLabel(start: recordingStartedAt, wordCount: nil)
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

    private var isError: Bool {
        if case .error = status { return true }
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
        case .permissionRequired: return mutedColor
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
        case .error(let message):  return message.uppercased()
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

// MARK: - ProcessingShimmerView
// Seven horizontally-arranged dots with a soft falloff. Used in place of
// breathing bars during .processing so we don't pretend to be listening.

private struct ProcessingShimmerView: View {
    let color: Color
    let animated: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: max(8, geo.size.width * 0.04)) {
                ForEach(0..<7, id: \.self) { index in
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                        .opacity(dotOpacity(for: index))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let position = (CGFloat(index) / 6.0)
        let center = phase
        let dist = abs(position - center.truncatingRemainder(dividingBy: 1.0))
        let wrapped = min(dist, 1 - dist)
        return Double(0.15 + 0.65 * exp(-pow(wrapped * 3.0, 2)))
    }
}

// MARK: - TimerLabel
// Live elapsed-time label shown to the right of LISTENING.

private struct TimerLabel: View {
    let start: Date?
    @State private var now: Date = Date()

    private let formatter: DateComponentsFormatter = {
        let componentsFormatter = DateComponentsFormatter()
        componentsFormatter.unitsStyle = .positional
        componentsFormatter.zeroFormattingBehavior = .pad
        componentsFormatter.allowedUnits = [.minute, .second]
        return componentsFormatter
    }()

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .tracking(0.5)
            .onAppear { now = Date() }
            .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
                now = Date()
            }
    }

    private var label: String {
        guard let start = start else { return "00:00" }
        let dt = max(0, now.timeIntervalSince(start))
        return formatter.string(from: dt) ?? "00:00"
    }
}

// MARK: - HotkeyHint
// Compact keycap shown on .ready so users know how to invoke the app.

private struct HotkeyHint: View {
    var body: some View {
        Text("⌘⇧Space")
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            )
    }
}

// MARK: - SuccessRecapLabel
// On success, show how long the recording was. Pass a word count from the
// view-model if you want to surface "N words · M.Ms".

private struct SuccessRecapLabel: View {
    let start: Date?
    let wordCount: Int?

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .regular))
            .tracking(0.4)
    }

    private var label: String {
        let dur = start.map { Date().timeIntervalSince($0) } ?? 0
        let secs = String(format: "%.1fs", dur)
        if let count = wordCount, count > 0 { return "\(count) words · \(secs)" }
        return secs
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
