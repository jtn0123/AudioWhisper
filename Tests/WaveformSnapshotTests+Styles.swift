import SwiftUI
@testable import AudioWhisper

// The non-classic styles, split out of WaveformSnapshotTests to keep each type
// within SwiftLint's body-length limit.
@MainActor
extension WaveformSnapshotTests {
    // MARK: - Additional Waveform Style Snapshots (D3)
    //
    // The existing waveform tests only exercise the `classic` style. These add
    // baselines for the remaining 5 styles so visual regressions in any one
    // renderer are caught by the snapshot suite.

    private static let sampleWaveformSamples: [Float] = (0..<64).map { index in
        // Deterministic pseudo-samples so the snapshot is stable across runs.
        let phase = Float(index) * 0.25
        return sin(phase) * 0.4 + cos(phase * 1.7) * 0.2
    }

    private static let sampleFrequencyBands: [Float] = [
        0.85, 0.70, 0.60, 0.50, 0.40, 0.30, 0.22, 0.15
    ]

    func testWaveformContainerNeonDarkSnapshot() {
        defaults.set(WaveformStyle.neon.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-neon-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark,
            tolerance: 0.02  // animated view — measured nondeterministic
        )
    }

    func testWaveformContainerSpectrumDarkSnapshot() {
        defaults.set(WaveformStyle.spectrum.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-spectrum-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark,
            tolerance: 0.05  // animated view — measured nondeterministic
        )
    }

    // The redesign replaced the old circular/pulseRings/particles styles with
    // halo/heartbeat/stream. These exercise the new renderers through the
    // WaveformContainer's style switch so visual regressions are caught.
    func testWaveformContainerHaloDarkSnapshot() {
        defaults.set(WaveformStyle.halo.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-halo-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark,
            tolerance: 0.03  // animated view — measured nondeterministic
        )
    }

    func testWaveformContainerHeartbeatDarkSnapshot() {
        defaults.set(WaveformStyle.heartbeat.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-heartbeat-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark,
            tolerance: 0.05  // animated view — frame content varies per render
        )
    }

    func testWaveformContainerStreamDarkSnapshot() {
        defaults.set(WaveformStyle.stream.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-stream-dark",
            size: CGSize(width: 320, height: 200),
            colorScheme: .dark,
            tolerance: 0.05  // animated view — measured nondeterministic
        )
    }

    // Light-mode contrast: spectrum genuinely looks different against a
    // light background because the bg color is themed.
    func testWaveformContainerSpectrumLightSnapshot() {
        defaults.set(WaveformStyle.spectrum.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: Self.sampleWaveformSamples,
            frequencyBands: Self.sampleFrequencyBands,
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "Waveform-spectrum-light",
            size: CGSize(width: 320, height: 200),
            colorScheme: .light,
            tolerance: 0.05  // animated view — measured nondeterministic
        )
    }

    // Classic recording in light mode — complements the existing dark variant
    // so the recording-state visual is locked down across color schemes.
    func testWaveformContainerClassicRecordingLightSnapshot() {
        defaults.set(WaveformStyle.classic.rawValue, forKey: "waveformStyle")
        defaults.set(VisualIntensity.balanced.rawValue, forKey: "visualIntensity")

        let view = WaveformContainer(
            status: .recording,
            audioLevel: 0.5,
            waveformSamples: [],
            frequencyBands: Array(repeating: 0.5, count: 8),
            onTap: {}
        )
        .frame(width: 280, height: 160)

        assertSnapshot(
            view,
            named: "WaveformContainer-classic-recording-light",
            size: CGSize(width: 320, height: 200),
            colorScheme: .light,
            tolerance: 0.05  // animated view — frame content varies per render
        )
    }
}
