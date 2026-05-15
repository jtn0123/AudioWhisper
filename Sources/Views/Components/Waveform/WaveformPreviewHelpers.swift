import SwiftUI
import Combine

// MARK: - LivePreviewSampler
//
// Emits synthetic audio data so waveform style previews can animate while the
// app isn't actually recording. Used by both the Visuals settings grid and
// the consolidated Welcome screen.
//
// Idle mode: audioLevel ~0.2 with gentle envelope — used by tiles in the grid
// to keep all 8 alive but quiet.
// Active mode: full envelope + jitter — used for the big "preview window"
// that simulates a live recording.

@MainActor
final class LivePreviewSampler: ObservableObject {
    @Published var audioLevel: Float = 0.2
    @Published var samples: [Float] = []
    @Published var bands: [Float] = []
    @Published var sincePeak: TimeInterval = 10

    /// When false, audio level stays low. When true, full envelope.
    var isActive: Bool = true

    private var timer: AnyCancellable?
    private var time: Double = 0
    private var lastPeakAt: Double = -10

    func start() {
        guard timer == nil else { return }
        // ~30 FPS
        timer = Timer.publish(every: 0.033, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        time += 0.033

        // Envelope — slow varying
        let env = 0.45 + 0.25 * sin(time * 0.7) + 0.15 * sin(time * 1.8)
        let active = max(0.15, min(1.0, env))
        let idle = 0.18 + 0.08 * sin(time * 1.2)
        audioLevel = Float(isActive ? active : idle)

        // 64 samples
        samples = (0..<64).map { index in
            let phase = time * 3 + Double(index) * 0.18
            return Float(sin(phase) * 0.45 + sin(phase * 2.3) * 0.15)
        }

        // 8 bands
        bands = (0..<8).map { index in
            let phase = time * (0.8 + Double(index) * 0.25) + Double(index) * 0.7
            let env2 = 0.4 + sin(phase) * 0.3
            let fast = sin(time * 8 + Double(index) * 1.7) * 0.1
            return Float(max(0.05, min(1.0, env2 + fast)) * Double(audioLevel) * 1.1)
        }

        // Peak detection (used by Heartbeat)
        if audioLevel > 0.55 && (time - lastPeakAt) > 0.4 {
            lastPeakAt = time
        }
        sincePeak = time - lastPeakAt
    }
}

// MARK: - WaveformStylePreview
//
// Renders any waveform style with data from a LivePreviewSampler. Used by
// the picker grid and the big preview window.

internal struct WaveformStylePreview: View {
    let style: WaveformStyle
    @ObservedObject var sampler: LivePreviewSampler

    var body: some View {
        switch style {
        case .classic:
            ClassicWaveformView(
                audioLevel: sampler.audioLevel,
                isActive: true,
                barColor: Color(red: 0.85, green: 0.83, blue: 0.80)
            )
        case .neon:
            NeonWaveformView(
                waveformSamples: sampler.samples,
                audioLevel: sampler.audioLevel,
                isActive: true
            )
        case .spectrum:
            SpectrumWaveformView(
                frequencyBands: sampler.bands,
                isActive: true
            )
        case .stream:
            StreamWaveformView(
                audioLevel: sampler.audioLevel,
                isActive: true
            )
        case .constellation:
            ConstellationWaveformView(
                audioLevel: sampler.audioLevel,
                isActive: true
            )
        case .halo:
            HaloWaveformView(
                frequencyBands: sampler.bands,
                audioLevel: sampler.audioLevel,
                isActive: true
            )
        case .dial:
            DialWaveformView(
                frequencyBands: sampler.bands,
                audioLevel: sampler.audioLevel,
                isActive: true
            )
        case .heartbeat:
            HeartbeatPulseView(
                audioLevel: sampler.audioLevel,
                isActive: true
            )
        }
    }
}
